import contextlib
import io
import os
import tempfile
import wave
from contextlib import asynccontextmanager
from pathlib import Path

from basic_pitch import ICASSP_2022_MODEL_PATH
from basic_pitch.inference import Model, predict
from fastapi import Body, FastAPI, Form, HTTPException, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app import synth
from app.songs import jobs
from app.harmony import without_overtones
from app.notes import midi_to_note_name
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
    meter: int = Form(4),
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

    notes = transcribe(audio_path)
    result = analyze_notes(notes, bpm=bpm, first_beat=first_beat, meter=meter)

    # A song, or chords on one instrument: the quick melody-based answer
    # comes back now, and the real progression follows from a background
    # job the app polls (GET /jobs/{id}).
    if result["route"] in ("full_mix", "polyphonic"):
        from app.songs import models

        if models.available():
            from app.songs.pipeline import analyze_song

            route = result["route"]
            job_id = jobs.start(lambda progress: analyze_song(audio_path, transcribe, route, progress))
            result["job"] = {"id": job_id, "status": "running"}
            result["route_note"] = "Listening to each instrument to find the song's own chords…"
    return result


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
