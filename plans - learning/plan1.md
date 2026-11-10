# Music Copilot — Note Recognition MVP

## Context

The long-term goal is a "music copilot" mobile app: record or upload
music, recognize notes (via a neural net / ML model), convert to
chords, detect scale and key, and explain the music theory to the
user in plain language. That's a large, multi-subsystem project, so
this plan scopes down to the first slice only: **record audio in a
mobile app, run it through Spotify's open-source Basic Pitch model,
and display the recognized notes to the user.** Later slices (chords,
scale/key detection, theory explanations) will each get their own
design pass once this foundation works.

The user is new to mobile development (has web dev experience) and
explicitly wants to learn the tools as we go — both the Flutter/Dart
app side and, eventually, the ML concepts behind note/chord/key
recognition. This plan documents an architecture plus a concept
checklist so the user can look up what they don't yet understand
while reading the code we produce.

## Architecture

Two components in one repo (`music_copilot/`):

- **`app/`** — a Flutter (Dart) mobile app. Chosen over native
  iOS/Android because it's closer to a "build once, learn once" path
  and can later target both iOS and Android from the same codebase.
  Developed and tested against the iOS Simulator.
- **`backend/`** — a small Python FastAPI server wrapping the
  `basic-pitch` pip package (Spotify's open-source note-recognition
  model). The app uploads a recorded audio clip; the backend runs
  Basic Pitch on it and returns detected notes as JSON.

Running Basic Pitch server-side (rather than converting it to run
on-device) was chosen because: it runs as-is with no model
conversion, and it gives the user a real backend to learn deployment
on later — matching their stated interest in understanding both the
front end and back end of the app.

No cloud deployment yet — the backend runs on `localhost` for now,
reachable directly from the iOS Simulator (which shares the host's
network). Deployment is a deliberate future step, not part of this
slice.

## Data flow

1. User taps record in the Flutter app → records audio to a local
   file using the `record` package.
2. App POSTs the audio file to the backend's `/analyze` endpoint
   (multipart upload) using the `http` package.
3. Backend runs `basic_pitch.inference.predict()` on the file, which
   returns note events (pitch, start time, end time, confidence).
4. Backend converts MIDI pitch numbers to note names (e.g. 60 → "C4")
   and returns a JSON list of notes.
5. App parses the JSON and renders it as a scrollable list: note
   name, start–end time, confidence. (Piano-roll and sheet-music
   views are explicitly deferred to a later slice.)

## Components to build

- `backend/app/main.py` — FastAPI app, single `POST /analyze`
  endpoint: accepts an audio file upload, calls Basic Pitch, formats
  the response as JSON.
- `backend/requirements.txt` — `fastapi`, `uvicorn`, `basic-pitch`,
  `python-multipart`.
- `app/lib/main.dart` — app entry point and basic navigation between
  a record screen and a results screen.
- `app/lib/screens/record_screen.dart` — mic button, start/stop
  recording, triggers upload on stop.
- `app/lib/screens/results_screen.dart` — renders the note list
  returned from the backend.
- `app/lib/services/api_service.dart` — handles the HTTP multipart
  upload to the backend and JSON parsing.

## Concepts to learn

Organized by the part of the code you'll be reading, roughly in the
order you'll hit them.

**Dart language basics** (needed to read any Flutter file)
- Variables, types, functions, classes/objects
- `async`/`await` and `Future` — Dart's way of handling things that
  take time (like network calls), used constantly in `api_service.dart`
- Null safety (`?`, `!`) — Dart's type system tracks what can be null

**Flutter app structure** (needed to read `main.dart` and the screens)
- Widgets — everything in a Flutter UI is a widget; `StatelessWidget`
  vs `StatefulWidget` (state = data that can change and redraw the UI)
- The widget tree and `build()` method — how widgets nest to form a screen
- `setState()` — how a `StatefulWidget` tells Flutter "redraw me,
  something changed" (e.g. recording started, notes came back)
- Navigation (`Navigator.push`) — how the app moves from the record
  screen to the results screen
- `pubspec.yaml` and packages (pub.dev) — Flutter's equivalent of
  `package.json`/npm, declares dependencies like `record` and `http`

**Audio recording on-device**
- Microphone permissions (iOS `Info.plist` entries, runtime permission
  prompts)
- What the `record` package is doing: capturing raw audio and
  encoding it to a file (e.g. `.wav`/`.m4a`)

**Talking to the backend**
- REST API basics — HTTP methods (`POST`), status codes, JSON as the
  data format
- Multipart form uploads — how a file (the audio) gets sent over HTTP
  alongside a JSON-returning API
- What FastAPI is doing: routing a `POST /analyze` request to a
  Python function, validating input, returning a JSON response
- Running a local server: `uvicorn`, `localhost`, ports, and why the
  iOS Simulator can reach `localhost` directly (a physical phone
  can't, and would need your machine's LAN IP)
- Python virtual environments and `pip install -r requirements.txt`

**The ML side (Basic Pitch, today and going forward)**
- What "audio-to-MIDI transcription" means: turning a raw waveform
  into discrete notes (pitch + start/end time), as opposed to just
  classifying a whole clip
- Basic audio concepts the model works with: sample rate, waveform,
  and the CQT (Constant-Q Transform) — a spectrogram-like
  representation that spaces frequencies the way musical pitches are
  spaced (used internally by Basic Pitch instead of a raw waveform)
- MIDI note numbers and how they map to note names + octave (e.g.
  60 = C4) — this is the translation layer in `backend/app/main.py`
- Onset/frame/pitch-bend outputs and confidence scores — Basic
  Pitch's model doesn't just say "this note happened," it scores how
  confident it is, and separately detects *when* a note starts
  (onset) vs. that a note is *sustained* (frame) — worth understanding
  since it explains the shape of the JSON the backend returns
- (Forward-looking, not needed yet) Convolutional Neural Networks
  (CNNs) — Basic Pitch's model architecture, worth learning once
  you're ready to look inside the model rather than treat it as a
  black box
- (Forward-looking) Key/scale-detection algorithms, e.g. the
  Krumhansl-Schmuckler key-finding algorithm — relevant once we build
  the scale/key-recognition slice; this is more classical
  music-theory-informed statistics than deep learning
- (Forward-looking) Chord recognition from note sets — mapping
  intervals between simultaneous notes to chord names; a rules/lookup
  problem more than an ML one, relevant for the next slice after this

## Verification

1. **Backend**: run `uvicorn app.main:app --reload` from `backend/`,
   then `curl` a sample `.wav` file to `POST /analyze` and confirm a
   sensible JSON note list comes back (pitch names, start/end times).
2. **App**: run in the iOS Simulator, record a short hum or a few
   piano notes, confirm the note list screen appears and the notes
   look plausible against what was played.
3. No automated tests are in scope for this first slice — the goal is
   an end-to-end usable path, verified manually as above.

## Out of scope for this slice (explicitly deferred)

- Chord recognition, scale/key detection, music theory explanations
- Piano-roll or sheet-music visualization
- Cloud deployment / hosting the backend anywhere but localhost
- Android testing (Flutter supports it, but iOS Simulator is the dev
  target for now)
- Automated test suite