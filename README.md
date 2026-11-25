# Music Copilot

A music copilot: record or upload music, recognize notes, and (eventually)
convert them to chords, detect scale/key, and explain the music theory.

This is the first slice: **record audio in a mobile app, run it through
Spotify's open-source [Basic Pitch](https://github.com/spotify/basic-pitch)
model, and display the recognized notes.**

See [`docs/concepts.md`](docs/concepts.md) for a learning checklist covering
everything used in this codebase, from Dart/Flutter basics to the ML
concepts behind Basic Pitch.

## Quick start

With Python 3.11 and Flutter installed, from the repo root:

```bash
./dev.sh
```

It sets up or updates the backend's Python packages when needed, starts the
backend, serves the app at `http://localhost:8080` and opens it in your
browser. `r` / `R` in that terminal reload the app; `Ctrl+C` stops everything.
Backend output goes to `.dev/backend.log`. Leftover servers from an earlier
run are stopped automatically; anything else using ports 8000 or 8080 is
reported, not touched.

The manual steps it automates are below.

## Structure

- `backend/` — Python FastAPI server that runs Basic Pitch on an uploaded
  audio file and returns detected notes as JSON.
- `app/` — Flutter mobile app: record audio, upload it to the backend,
  display the returned notes.

## Backend setup

Requires Python 3.11 (Basic Pitch's ML dependencies don't yet support the
very latest Python releases, so a pinned 3.11 venv is used instead of the
system Python), and `ffmpeg` on your `PATH` (`brew install ffmpeg` on a Mac)
for decoding uploaded MP3/M4A files — WAV/FLAC/OGG work without it.

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

### Desktop app

The desktop app starts the backend itself, so there's nothing else to run:

```bash
cd app
flutter run -d macos   # or -d windows / -d linux
```

On launch it checks `http://127.0.0.1:8000/health`. If a backend is already
running (say from `./dev.sh`) it uses that one; otherwise it runs
`backend/serve.py`, which creates `backend/venv` and installs the packages
the first time (a few minutes; progress shows in the sidebar), then starts
the server. Quitting the app stops the backend it started — even after a
crash, since `serve.py` exits once the app's end of its stdin pipe closes.

It finds the `backend` folder by looking upwards from where the app runs,
which works for any build inside this repository. Elsewhere, set
`MUSIC_COPILOT_BACKEND=/path/to/backend` (environment variable or
`--dart-define`). It needs Python 3.11 for the first setup, looked for on
`PATH` and in Homebrew's folders (`MUSIC_COPILOT_PYTHON` overrides it; on
Windows it uses `py -3.11`). On macOS the app sandbox is switched off in
`macos/Runner/*.entitlements`, since a sandboxed app can't run Python.

`serve.py` works on its own too: `python3.11 backend/serve.py`.

On a wide window the desktop app has its own interface: a sidebar with
record / import / click, this take's key, tempo and length, the analyzer's
status and the keyboard shortcuts (Space play/pause or stop recording, R
record, ⌘O / Ctrl+O import, L loop, Esc cancel or start over); the results
show a large contour with the parts and harmonies beside every chord idea
at once, and chord details open as dialogs. Narrow windows, and phones,
keep the mobile layout. A desktop browser wider than 900px gets the desktop
layout too, which makes it easy to try with `./dev.sh`.

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

Once the notes land, the detected chords draw themselves in as a band
between the notes and the waveform, each with its Roman numeral, and the key
appears in the corner. Tap a chord to hear it and light up the notes that
make it.

Tap a note, or the stretch of waveform it came from, to hear it. A playhead
sweeps the slice while it plays, and the note's duration stroke fills in.
`play` plays the whole recording (tap again to pause), lighting up each note
as it sounds. Tapping empty space stops playback. `redraw` re-runs the
animation.

`upload`, next to the record button while idle, analyzes an existing WAV,
MP3, or M4A file instead of a live recording. A WAV's waveform is decoded
exactly like a recording's; MP3/M4A can't be decoded into an exact envelope
client-side, so their "waveform" is a stand-in built from the detected
notes' timing and confidence once analysis comes back.
