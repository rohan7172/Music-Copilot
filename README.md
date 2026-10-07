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

Server runs at `http://127.0.0.1:8000`. It loads and warms up the Basic Pitch
model before accepting requests, so startup takes a few seconds and every
analysis after that is quick. Check it's alive:

```bash
curl http://127.0.0.1:8000/health
```

Alongside the notes, `/analyze` returns the detected `key` and `chords`
(name, Roman numeral, notes, start/end time), worked out from the notes in
`backend/app/harmony.py`. Run its tests with:

```bash
./venv/bin/pip install -r requirements-dev.txt
./venv/bin/pytest
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
physical device needs your machine's LAN IP instead:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

The app also runs in a browser (`flutter run -d chrome`), which is the quickest
way to iterate on the interface.

## Interface

A single canvas instead of separate record and results screens:

1. **Idle:** an off-white slate with a faint pen line and a breathing record button.
2. **Recording:** the line grows into a live waveform, left to right.
3. **Analyzing:** the recording's real envelope (decoded from the WAV) replaces
   the live one. A reading light sweeps across it, and small hint dots lift off
   its peaks.
4. **Settled:** each note arcs up from the point on the waveform where it began
   and lands in a pitch lane. Height is pitch, the stroke is duration, and
   opacity is confidence. A thread ties each note back to the slice of
   waveform it came from.

Tap a note, or the stretch of waveform it came from, to hear it. A playhead
sweeps the slice while it plays, and the note's duration stroke fills in.
`play` plays the whole recording (tap again to pause), lighting up each note
as it sounds. Tapping empty space stops playback. `redraw` re-runs the
animation.
