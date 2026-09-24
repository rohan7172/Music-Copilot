# Music Copilot

A music copilot: record or upload music, recognize notes, and (eventually)
convert them to chords, detect scale/key, and explain the music theory.

This is the first slice: **record audio in a mobile app, run it through
Spotify's open-source [Basic Pitch](https://github.com/spotify/basic-pitch)
model, and display the recognized notes.**

See [`docs/concepts.md`](docs/concepts.md) for a learning checklist covering
everything used in this codebase, from Dart/Flutter basics to the ML
concepts behind Basic Pitch.

## Structure

- `backend/` — Python FastAPI server that runs Basic Pitch on an uploaded
  audio file and returns detected notes as JSON.
- `app/` — Flutter mobile app: record audio, upload it to the backend,
  display the returned notes.

## Backend setup

Requires Python 3.11 (Basic Pitch's ML dependencies don't yet support the
very latest Python releases, so a pinned 3.11 venv is used instead of the
system Python).

```bash
cd backend
python3.11 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/uvicorn app.main:app --reload
```

Server runs at `http://127.0.0.1:8000`. Check it's alive:

```bash
curl http://127.0.0.1:8000/health
```

Analyze an audio file:

```bash
curl -F "file=@/path/to/clip.wav;type=audio/wav" http://127.0.0.1:8000/analyze
```

## App setup

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) and,
for iOS, full Xcode (not just the Command Line Tools) with an iOS Simulator
runtime installed.

```bash
cd app
flutter pub get
flutter run
```

The app expects the backend at `http://127.0.0.1:8000` by default, which
works from the iOS Simulator since it shares the host machine's network. A
physical device needs your machine's LAN IP instead (see
`app/lib/services/api_service.dart`).
