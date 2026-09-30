import tempfile
from pathlib import Path

from basic_pitch.inference import predict
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.notes import midi_to_note_name

app = FastAPI(title="Music Copilot Backend")

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

        _, _, note_events = predict(tmp.name)

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
