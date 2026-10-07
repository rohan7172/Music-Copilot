import tempfile
import wave
from contextlib import asynccontextmanager
from pathlib import Path

from basic_pitch import ICASSP_2022_MODEL_PATH
from basic_pitch.inference import Model, predict
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.notes import midi_to_note_name

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
async def analyze(file: UploadFile) -> dict:
    if file.content_type is None or not file.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be an audio file")

    suffix = Path(file.filename or "audio").suffix or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp.flush()

        _, _, note_events = predict(tmp.name, _model)

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

    return {"notes": notes}
