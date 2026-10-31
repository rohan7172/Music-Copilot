import contextlib
import io
import os
import traceback
import tempfile
import wave
from contextlib import asynccontextmanager
from pathlib import Path

from basic_pitch import ICASSP_2022_MODEL_PATH
from basic_pitch.inference import Model, predict
from fastapi import Body, FastAPI, Form, HTTPException, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool

from app import synth
from app.songs import jobs
from app.harmony import without_overtones
from app.notes import midi_to_note_name
from app.melody import classify_input, percussive_share_samples
from app.onset import music_start_samples, trim_notes
from app.pipeline import analyze_notes, suggest
from app.timing import BeatGrid


def _load_env() -> None:
    """Reads backend/.env (gitignored) for secrets like GEMINI_API_KEY,
    without overriding anything already set in the environment."""
    env = Path(__file__).resolve().parent.parent / ".env"
    if not env.exists():
        return
    for line in env.read_text().splitlines():
        name, sep, value = line.strip().partition("=")
        if sep and name and not name.startswith("#"):
            os.environ.setdefault(name.strip(), value.strip().strip('"').strip("'"))


_load_env()

_model: Model | None = None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Load Basic Pitch once, before the server accepts requests.

    Without this, every request rebuilds the model and the first one also pays
    TensorFlow's one-time setup, so the first analysis is several seconds slow.
    """
    global _model
    _model = Model(ICASSP_2022_MODEL_PATH)

    # Warm-up: run one second of silence through it so that setup happens now.
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as silence:
            silence.setnchannels(1)
            silence.setsampwidth(2)
            silence.setframerate(22050)
            silence.writeframes(b"\x00\x00" * 22050)
        predict(tmp.name, _model)

    yield


app = FastAPI(title="Music Copilot Backend", lifespan=lifespan)

# Lets the Flutter web build (served from a different port) call the API
# during local development.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/analyze")
async def analyze(
    file: UploadFile,
    bpm: float | None = Form(None),
    first_beat: float | None = Form(None),
    meter: int | None = Form(None),
) -> dict:
    """Transcribes the audio and suggests progressions for its melody.
    `bpm` and `first_beat` (seconds) come from the app's click, when one was
    used; otherwise the beat grid is estimated."""
    if file.content_type is None or not file.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be an audio file")

    suffix = Path(file.filename or "audio").suffix or ".wav"
    # Kept on disk (not a with-block temp file): a song job reads it later.
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        audio_path = tmp.name

    # The heavy work (transcription, beats, chord recognition) runs in a
    # worker thread: done directly in this async handler it would block
    # the event loop, stalling every other request (job polling included).
    return await run_in_threadpool(_analyze_file, audio_path, bpm, first_beat, meter)


def _analyze_file(audio_path: str, bpm: float | None, first_beat: float | None, meter: int | None) -> dict:
    import librosa

    clipped = _clip_long_audio(audio_path)
    if clipped:
        audio_path = clipped
    notes = transcribe(audio_path)
    # Loaded once for both measurements, rather than once each.
    try:
        y, sr = librosa.load(audio_path, sr=22050, mono=True, duration=_MAX_SECONDS)
        start = music_start_samples(y, sr)
        percussive = percussive_share_samples(y, sr)
    except Exception:
        start, percussive = 0.0, 0.0
    route = classify_input(trim_notes(notes, start), percussive)

    # Chords on one instrument, or a song: recognise the chords from the
    # audio now (beats + BTC + beat-synchronous decoding, no separation:
    # a second or two), so the first answer is what was actually played,
    # not guesses built from the top line. A song then also gets a
    # background job that separates the parts (vocal melody, bass, stems)
    # and refines it; the app polls GET /jobs/{id}.
    song = route in ("full_mix", "polyphonic")
    if song:
        from app.songs import models

        song = models.available()
    result = None
    if song:
        from app.songs.pipeline import analyze_song

        try:
            quick = analyze_song(
                audio_path,
                transcribe,
                "polyphonic",
                notes=notes,
                start=start,
                # A full mix's job re-harmonises from the vocal stem, so its
                # quick answer needs only the recognised chords.
                alternatives=route == "polyphonic",
            )
            result = {**quick, "route": route, "route_note": None}
        except Exception:
            # No steady beat, say: fall back to the melody-based answer.
            traceback.print_exc()
    if result is None:
        # A melody take, or the fallback: harmonise the top line. Only done
        # when needed, since for a song the quick recognition replaces it.
        result = analyze_notes(
            notes, bpm=bpm, first_beat=first_beat, meter=meter, percussive=percussive, music_start=start
        )
    if song and route == "full_mix":
        from app.songs.pipeline import analyze_song

        job_id = jobs.new_id()
        job_dir = _JOBS_DIR / job_id
        job_id = jobs.start(
            lambda progress: analyze_song(
                audio_path, transcribe, route, progress, work_dir=job_dir, start=start
            ),
            job_id,
        )
        result["job"] = {"id": job_id, "status": "running"}
        result["route_note"] = "Listening to each instrument to fill in the melody and bass…"
    return result


_MAX_SECONDS = 90.0


def _clip_long_audio(audio_path: str) -> str | None:
    """A long upload (a whole song) is analysed from its first 90 seconds;
    returns the path of that clip, or None if the audio is short enough."""
    import librosa
    import soundfile as sf

    try:
        if librosa.get_duration(path=audio_path) <= _MAX_SECONDS + 1:
            return None
        y, sr = librosa.load(audio_path, sr=44100, mono=False, duration=_MAX_SECONDS)
    except Exception:
        return None  # let transcription report a truly unreadable file
    clip = audio_path + ".clip.wav"
    sf.write(clip, y.T if y.ndim == 2 else y, sr)
    return clip


def transcribe(audio_path: str) -> list[dict]:
    """Basic Pitch's notes for an audio file, overtone ghosts removed."""
    # Basic Pitch prints diagnostics for every audio chunk; keep the log clean.
    with contextlib.redirect_stdout(io.StringIO()):
        _, _, note_events = predict(audio_path, _model)
    notes = [
        {
            "pitch": midi_to_note_name(int(pitch)),
            "midi_pitch": int(pitch),
            "start_time": round(float(start_time), 3),
            "end_time": round(float(end_time), 3),
            "confidence": round(float(amplitude), 3),
        }
        for start_time, end_time, pitch, amplitude, _pitch_bends in note_events
    ]
    notes.sort(key=lambda n: n["start_time"])
    return without_overtones(notes)


_JOBS_DIR = Path(tempfile.gettempdir()) / "music_copilot_jobs"


@app.get("/jobs/{job_id}/stems/{name}")
def stem(job_id: str, name: str) -> FileResponse:
    """One separated part of a song (vocals, bass, other, drums) as a WAV,
    for soloing it in the app."""
    from app.songs.pipeline import STEMS

    if name not in STEMS or not job_id.isalnum():
        raise HTTPException(status_code=404, detail="No such stem")
    path = _JOBS_DIR / job_id / f"{name}.wav"
    if not path.exists():
        raise HTTPException(status_code=404, detail="No such stem (the job may have expired)")
    return FileResponse(path, media_type="audio/wav")


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    """A song job's stage and progress, and its full result once done."""
    job = jobs.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="No such job (it may have expired)")
    return job


@app.post("/harmonise")
def harmonise_endpoint(body: dict = Body(...)) -> dict:
    """Re-suggests for an already-transcribed melody, after the user nudges
    the beat grid (downbeat, tempo, meter) or overrides the key. No audio,
    no transcription, so it's near-instant."""
    melody = body.get("melody") or []
    try:
        grid = BeatGrid.from_dict(body["grid"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=400, detail="A grid with bpm and downbeat is required")
    per_bar = 2 if body.get("per_bar") == 2 else 1
    return suggest(melody, grid, key=body.get("key"), per_bar=per_bar, use_llm=bool(body.get("use_llm", True)))


@app.post("/backing")
def backing(body: dict = Body(...)) -> Response:
    """A WAV of a progression's chords, to loop under the user's take."""
    chords = body.get("chords") or []
    duration = float(body.get("duration") or max((c["end_time"] for c in chords), default=0))
    if not chords or duration <= 0:
        raise HTTPException(status_code=400, detail="chords and a duration are required")
    return Response(content=synth.render(chords, duration), media_type="audio/wav")
