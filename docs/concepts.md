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

## Color as music theory (`harmonic_color.dart`)

- Tonic/subdominant/dominant function — the three broad "roles" a chord
  can play relative to the key: tonic (I, vi, iii) is rest/home,
  dominant (V, vii°) is tension pulling back toward tonic, subdominant
  (IV, ii) sits in between, moving away from home. This is the same
  grouping behind `explain.py`'s per-degree descriptions
  (`_BLURBS`) — the color system just gives it a visual form instead of
  a sentence
- `Color.lerp` — Flutter's way of blending linearly between two colors;
  used here to turn a 0..1 "tension" value per scale degree into a
  smooth lavender-to-coral gradient rather than hard-coded buckets
- Why this duplicates `explain.py`'s roman-numeral regex in Dart rather
  than asking the backend for a color or a degree number: the frontend
  already has the `roman` string on every chord, so parsing it client-
  side avoids a network round-trip or a backend response change for a
  purely cosmetic concern — a reasonable case for a small, deliberate
  duplication instead of a shared source of truth

## Ambient atmosphere (`key_color.dart`, `ScorePainter._paintAmbient`)

- Two different jobs for color, kept deliberately separate: `KeyColor`
  gives the *key* a fixed identity (G major always looks the same hue,
  with no theory attached), while `HarmonicColor` gives each *chord* a
  reading of its function within that key. One says "what key am I
  in," the other says "what is this chord doing right now."
- `HSLColor` — unlike `Color` (which is red/green/blue), `HSLColor` is
  hue/saturation/lightness: picking hues evenly spaced by degrees
  (`pitchClass * 30°` for 12 keys) is far more natural in HSL than in
  RGB, where "evenly spaced" colors aren't obvious from the numbers
- `ui.Gradient.radial` — like the `ui.Gradient.linear` already used for
  the analyzing-sweep stroke, but centered and radiating outward; the
  way to paint a soft "glow" that fades to nothing rather than a hard
  circle
- Same hue, different saturation/lightness (`KeyColor.forTonicVivid`) —
  a cheap way to get a "bolder version of this same color" for a
  foreground element (the waveform) without it reading as an unrelated
  color from the soft ambient wash behind it
- Alpha alone isn't enough for contrast: a color at 10% opacity over a
  light background reads as a tinted gray no matter how saturated the
  color itself is — getting a foreground element to actually "pop"
  needs the opacity to climb too, not just the hue to change
- `Curves.easeOutBack` — an easing curve that overshoots past its target
  before settling back, the standard way to get a "pop in" feel (used
  for the chord tabs' reveal and, combined with a second timestamp-driven
  scale bump, their tap feedback)
- A boolean toggle that *reads* as instant but *animates* as a fade:
  `Scene.faintToggleStart` records only a timestamp when "show faint
  notes" flips; the painter derives a smooth 0..1 progress from
  `now - faintToggleStart` every frame, the same pattern used
  everywhere else in this file for reveal animations (`settleStart`,
  `analyzeStart`, `morphStart`) — a toggle doesn't need its own
  animation controller, just one more timestamp
- Summed sine waves at different, unrelated frequencies as a cheap way
  to fake "organic" motion — a single `sin(t)` repeats in an obviously
  mechanical loop, but two or three summed together with frequencies
  that don't share a common period (so they don't realign for a very
  long time) reads as meandering rather than looping. The same idea
  already powered the record button's breathing and the hint dots'
  pulse, just with more terms layered in
- A `sin(π·x)` "bump" (zero at x=0, peak at x=0.5, zero again at x=1)
  as a reusable shape for anything that should rise and fall once
  rather than stay on — already used for the note-landing "pop," reused
  here for the chord-reveal pulses

## Picking an existing file (`audio/pick_audio_file.dart`)

- `file_picker` — the system file-picker UI, restricted here to
  `wav`/`mp3`/`m4a`; gives a real file path on native platforms, but only
  raw bytes on web (browsers don't expose a filesystem path)
- Data URIs (`Uri.dataFromBytes`) — a way to embed a file's bytes directly
  inside a URL (`data:audio/mpeg;base64,...`); used so the web build can
  hand `just_audio` something to play when there's no file path or blob
  URL available, unlike a live recording's blob URL
- `ffmpeg` as a backend system dependency — `librosa` (which Basic Pitch
  uses to load audio) decodes WAV/FLAC/OGG natively via `soundfile`, but
  falls back to `ffmpeg` for compressed formats like MP3/M4A; nothing to
  do with Python packages, it has to be installed separately on the host
- A synthetic "waveform" from note data (`Waveform.fromNoteActivity`) —
  when the real audio can't be decoded into samples client-side, the
  canvas shows note density/confidence over time instead; not the actual
  sound, but a visualization that still reflects what was heard

## Audio recording and playback on-device

- Microphone permissions (iOS `Info.plist` entries, runtime permission
  prompts)
- What the `record` package is doing: capturing raw audio and encoding it
  to a file (e.g. `.wav`/`.m4a`)
- `just_audio` — playing back a recording or a slice of it; seeking to a
  position, tracking playback state
- `audio_session` — why recording and playback need different "modes" on
  iOS (recording can otherwise route playback to the earpiece speaker)
- Why `session_screen.dart` has several small playback methods
  (`_playRange`, `_togglePlayAll`, `_playFromHere`) instead of one
  generalized one: they differ in exactly one thing — where `_playEnd`
  stops — and keeping that fixed point explicit per-method is easier to
  read and safer to change than threading extra parameters through a
  single do-everything function

## The mascot and splash screen (`widgets/mascot.dart`, `screens/splash_screen.dart`)

- Reusing the `CustomPainter` + pure-state-mapping pattern for a second,
  unrelated character: `expressionForPhase` is a plain `Phase ->
  MascotExpression` function (no `Canvas`, no animation state), unit
  tested directly (`test/mascot_test.dart`) — the same separation of
  "what state are we in" from "how do we draw it" used throughout
  `score_canvas.dart`, and the same reasoning behind keeping
  `harmonic_color.dart`/`key_color.dart` as their own files
- The "stadium" shape trick: `RRect.fromRectAndRadius` with a corner
  radius of half the *shorter* side turns a plain rounded rectangle into
  a full capsule/pill — no separate "pill" drawing code needed, just the
  right radius relative to the box (used for both the mascot's body and
  the `_QuietButton` chips, via the shared `Shape.pill` constant)
- `AnimationController` as a *bounded*, one-shot alternative to the
  free-running `Ticker`/clock pattern used everywhere else: the splash
  needs a fixed-length sequence with a "done" callback (`addStatusListener`,
  `AnimationStatus.completed`), which `AnimationController` gives for
  free, rather than hand-rolling an end-time check against the shared
  clock
- `PageRouteBuilder` + `FadeTransition` — a custom, minimal screen
  transition (a plain cross-fade) instead of the platform's default
  slide, used to move from the splash into the session screen
- Programmatic audio synthesis (`scripts/generate_splash_chime.py`): a
  sine wave sampled at 44.1kHz, scaled to 16-bit PCM integers, and
  wrapped in a WAV header (Python's `wave` module) — enough to generate
  a short, deterministic sound asset from code instead of sourcing an
  audio file; a linear fade in/out on each note avoids the audible
  "click" a hard-edged tone would otherwise have
- `StadiumBorder` + `Material`/`InkWell` — Flutter's way to get a
  custom-shaped tappable surface (here, a pill) that still shows the
  platform's ink-ripple feedback on tap, rather than a plain
  `GestureDetector` with no visual response

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
