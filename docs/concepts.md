# Concepts to learn

Organized by the part of the code you'll be reading, roughly in the order
you'll hit them.

## Dart language basics

Needed to read any file in `app/lib/`.

- Variables, types, functions, classes/objects
- `async`/`await` and `Future` — Dart's way of handling things that take
  time (like network calls), used constantly in `api_service.dart`
- Null safety (`?`, `!`) — Dart's type system tracks what can be null

## Flutter app structure

Needed to read `main.dart` and the screens.

- Widgets — everything in a Flutter UI is a widget; `StatelessWidget` vs
  `StatefulWidget` (state = data that can change and redraw the UI)
- The widget tree and `build()` method — how widgets nest to form a screen
- `setState()` — how a `StatefulWidget` tells Flutter "redraw me, something
  changed" (e.g. recording started, notes came back)
- Navigation (`Navigator.push`) — how the app moves from the record screen
  to the results screen
- `pubspec.yaml` and packages (pub.dev) — Flutter's equivalent of
  `package.json`/npm, declares dependencies like `record` and `http`

## Audio recording on-device

- Microphone permissions (iOS `Info.plist` entries, runtime permission
  prompts)
- What the `record` package is doing: capturing raw audio and encoding it
  to a file (e.g. `.wav`/`.m4a`)

## Talking to the backend

- REST API basics — HTTP methods (`POST`), status codes, JSON as the data
  format
- Multipart form uploads — how a file (the audio) gets sent over HTTP
  alongside a JSON-returning API
- What FastAPI is doing: routing a `POST /analyze` request to a Python
  function, validating input, returning a JSON response
- Running a local server: `uvicorn`, `localhost`, ports, and why the iOS
  Simulator can reach `localhost` directly (a physical phone can't, and
  would need your machine's LAN IP)
- Python virtual environments and `pip install -r requirements.txt`

## The ML side (Basic Pitch, today and going forward)

- What "audio-to-MIDI transcription" means: turning a raw waveform into
  discrete notes (pitch + start/end time), as opposed to just classifying
  a whole clip
- Basic audio concepts the model works with: sample rate, waveform, and
  the CQT (Constant-Q Transform) — a spectrogram-like representation that
  spaces frequencies the way musical pitches are spaced (used internally
  by Basic Pitch instead of a raw waveform)
- MIDI note numbers and how they map to note names + octave (e.g. 60 =
  C4) — this is the translation layer in `backend/app/notes.py`
- Onset/frame/pitch-bend outputs and confidence scores — Basic Pitch's
  model doesn't just say "this note happened," it scores how confident it
  is, and separately detects *when* a note starts (onset) vs. that a note
  is *sustained* (frame) — worth understanding since it explains the
  shape of the JSON the backend returns

### Forward-looking (not needed yet, for later slices)

- Convolutional Neural Networks (CNNs) — Basic Pitch's model architecture,
  worth learning once you're ready to look inside the model rather than
  treat it as a black box
- Key/scale-detection algorithms, e.g. the Krumhansl-Schmuckler
  key-finding algorithm — relevant once we build the scale/key-recognition
  slice; this is more classical music-theory-informed statistics than
  deep learning
- Chord recognition from note sets — mapping intervals between
  simultaneous notes to chord names; a rules/lookup problem more than an
  ML one, relevant for the next slice after this
