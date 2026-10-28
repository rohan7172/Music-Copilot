# Concepts to learn

Organized by the part of the code you'll be reading, roughly in the order
you'll hit them. Kept in sync with the codebase — when a feature introduces
a genuinely new concept, it gets added here.

## Dart language basics

Needed to read any file in `app/lib/`.

- Variables, types, functions, classes/objects
- `async`/`await` and `Future` — Dart's way of handling things that take
  time (like network calls), used constantly in `api_service.dart`
- Null safety (`?`, `!`) — Dart's type system tracks what can be null

## Flutter app structure

Needed to read `main.dart` and `screens/session_screen.dart`.

- Widgets — everything in a Flutter UI is a widget; `StatelessWidget` vs
  `StatefulWidget` (state = data that can change and redraw the UI)
- The widget tree and `build()` method — how widgets nest to form a screen
- `setState()` — how a `StatefulWidget` tells Flutter "redraw me, something
  changed" (e.g. recording started, notes came back)
- `pubspec.yaml` and packages (pub.dev) — Flutter's equivalent of
  `package.json`/npm, declares dependencies like `record` and `http`
- `Ticker`/`AnimationController` — Flutter's per-frame clock, used in
  `session_screen.dart` to drive the waveform/note animations and track
  playback position every frame
- `CustomPainter` (`widgets/score_canvas.dart`) — drawing directly onto a
  canvas with primitives (paths, arcs, text) instead of composing widgets;
  how the waveform, note arcs, and chord bands are actually rendered

## Audio recording and playback on-device

- Microphone permissions (iOS `Info.plist` entries, runtime permission
  prompts)
- What the `record` package is doing: capturing raw audio and encoding it
  to a file (e.g. `.wav`/`.m4a`)
- `just_audio` — playing back a recording or a slice of it; seeking to a
  position, tracking playback state
- `audio_session` — why recording and playback need different "modes" on
  iOS (recording can otherwise route playback to the earpiece speaker)

## Talking to the backend

- REST API basics — HTTP methods (`POST`), status codes, JSON as the data
  format
- Multipart form uploads — how a file (the audio) gets sent over HTTP
  alongside a JSON-returning API
- What FastAPI is doing: routing a `POST /analyze` request to a Python
  function, validating input, returning a JSON response
- CORS (Cross-Origin Resource Sharing) — why the backend needs
  `CORSMiddleware` for the Flutter *web* build (served from a different
  port) to be allowed to call it; not needed for the native iOS/Android app
- Running a local server: `uvicorn`, `localhost`, ports, and why the iOS
  Simulator (and a web build in your own browser) can reach `localhost`
  directly, while a physical phone needs your machine's LAN IP
- Python virtual environments and `pip install -r requirements.txt`
- Loading a model once at process startup (`main.py`'s `lifespan` +
  warm-up request) instead of per-request — a general web-server pattern
  for anything expensive to initialize, not specific to ML

## Note recognition: an actual ML model (Basic Pitch)

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
  is *sustained* (frame)
- Convolutional Neural Networks (CNNs) — Basic Pitch's model architecture,
  worth learning once you're ready to look inside the model rather than
  treat it as a black box

## Key and chord detection: NOT machine learning (`backend/app/harmony.py`)

Worth being explicit about this distinction: nothing below is a trained
model. It's classical music-theory algorithms and signal-processing
techniques, written out as ordinary code.

- Pitch class / chroma vectors — collapsing notes to "which of the 12
  pitches is sounding," ignoring octave; the basis for both key and chord
  detection (`_chroma()`)
- The Krumhansl-Schmuckler key-finding algorithm — correlates the chroma
  against fixed, empirically-measured "key profiles" (how strongly each
  scale degree is felt to belong to a key); used via `music21`'s
  `stream.analyze("krumhansl")`, not trained by this project
- Chord template matching — scoring the chroma at each moment against a
  fixed set of chord shapes (root + quality, e.g. "C major" = pitch
  classes 0, 4, 7) rather than recognizing a chord as a single learned
  pattern
- The Viterbi algorithm — dynamic programming over a sequence of
  per-frame guesses to find the single most likely *path* through time,
  penalizing rapid switching so a chord holds steady instead of
  flickering frame to frame; the same core technique behind classic
  speech recognition and other hidden-Markov-style problems
- Roman numeral analysis — naming a chord by its scale degree and
  function within a key (e.g. "V7" = the dominant seventh), rather than
  just its absolute name; `music21` does this spelling given the chord
  and the detected key
- `music21` — the Python music-theory library doing the key-profile
  correlation and Roman-numeral spelling; worth skimming its docs to see
  what else it can do

## Explaining the music in plain language (`backend/app/explain.py`)

- Why this is rule-based rather than an LLM call (for now): deterministic,
  no API key or per-request cost, and keeps the app usable offline/free —
  see the "Forward-looking" note below for where an LLM mode would plug in
- Regular expressions (`re` module) — used to parse a Roman numeral string
  like `"ii7"` or `"bVII"` down to its scale degree
- Mapping scale degrees to function (tonic/supertonic/mediant/
  subdominant/dominant/submediant/leading tone) — the standard
  music-theory vocabulary for "what role does this chord play"
- Cadences — recognizable chord-pair endings (authentic V–I, plagal
  IV–I, deceptive V–vi, half cadence ending on V) that give music a sense
  of resolution (or deliberately withheld resolution)

## Testing

- `pytest` (`backend/tests/`) — the backend's chord/key/explanation logic
  is tested directly against hand-built note/chord data, without needing
  real audio or the ML model
- `flutter test` (`app/test/`) — Dart model parsing (`Analysis.fromJson`
  and friends) is tested the same way, independent of the UI
- Red-green TDD — writing a test that fails for the right reason *before*
  writing the code that makes it pass, used for both `explain.py` and the
  Dart models above

## Forward-looking (not built yet)

- **LLM-based explanations** (e.g. Gemini) as a richer alternative to the
  rule-based templates above, likely gated behind a "mode" so the free
  rule-based path stays the default — see the `explanation` field's shape
  in `main.py`, designed to leave room for this without reshaping
- **Distinct scale/mode detection** — today "key" and "scale" are the same
  thing (major/minor only, via Krumhansl-Schmuckler); detecting modes
  (Dorian, Mixolydian, etc.) or non-diatonic scales would be a separate
  step
- **File upload / import** — the backend already accepts any audio file;
  the app only offers live recording so far
