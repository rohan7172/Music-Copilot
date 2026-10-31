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

Needed to read `main.dart`, `screens/session_screen.dart` and
`session/session_controller.dart`.

- Widgets — everything in a Flutter UI is a widget; `StatelessWidget` vs
  `StatefulWidget` (state = data that can change and redraw the UI)
- The widget tree and `build()` method — how widgets nest to form a screen
- `pubspec.yaml` and packages (pub.dev) — Flutter's equivalent of
  `package.json`/npm, declares dependencies like `record` and `http`
- `Ticker` — Flutter's per-frame clock. `SessionController` owns one and
  publishes "seconds since start" on a `ValueNotifier<double>` (`clock`);
  every animation in the app (mascot, fluid, contour, stream) is a pure
  function of that number rather than having its own animation controller
- `CustomPainter` — drawing directly onto a canvas with primitives (paths,
  arcs, text) instead of composing widgets; how the mascot, the edge
  fluid, the vocal contour and the acoustic stream are rendered.
  `super(repaint: clock)` makes a painter redraw every frame without
  rebuilding any widgets

## Separating state from screens (`session/session_controller.dart`)

The old app kept everything — microphone, backend call, playback, drawing
— in one 1,000-line `StatefulWidget`. The Stitch overhaul split that:

- `ChangeNotifier` — a plain Dart object that holds state and calls
  `notifyListeners()` when it changes. `SessionController` is one: it owns
  the recorder, player and API client, and exposes the phase, the
  results, `isPlaying`, `loop` and so on. It has no widgets in it, so the
  same logic could sit behind a completely different UI
- `ListenableBuilder` / `ValueListenableBuilder` — the widget side of the
  same idea: "rebuild this part of the tree when that object changes."
  `SessionScreen` rebuilds on the controller (discrete changes: phase,
  results, play/pause); small pieces like the recording timer or the
  "sounding now" label rebuild on `clock` (every frame) — so a per-frame
  change never rebuilds the whole screen
- One view per phase (`screens/views/`): `IdleView`, `ListeningView`
  (recording *and* analyzing — sharing one view is what lets the hand-off
  animate in place), `ResultsView`, `ErrorView`. `SessionScreen` just
  picks one and cross-fades with `AnimatedSwitcher`, keyed by a string so
  Flutter knows when the view really changed
- A test seam: `SessionScreen(createController: ...)` lets a test build the
  screen around a fake controller with hand-made results, which is how
  every screen state can be rendered and checked without a microphone,
  backend, or file picker

## A design system in code (`theme.dart`)

- Design tokens — colors, type sizes, radii and spacing defined once as
  named constants (`Palette.primary`, `TextStyles.headlineLg`,
  `Shape.panel`, `Space.md`) and referenced everywhere, never as raw
  values. They're copied from the Google Stitch project's Tailwind config,
  so "the design" and "the code" share one vocabulary
- Bundled fonts — the four Plus Jakarta Sans `.ttf` weights live in
  `app/assets/fonts/` and are declared under `fonts:` in `pubspec.yaml`
  (one `family`, one `asset` per `weight`). Bundling instead of fetching at
  runtime means text looks identical on every platform and offline
- Letter spacing units — CSS/Tailwind spacing is in `em` (relative to the
  font size); Flutter's `letterSpacing` is in logical pixels, so `0.06em`
  at 11px becomes `0.66`
- Tabular figures (`FontFeature.tabularFigures()`) — makes every digit the
  same width so a running clock (`00:16`) doesn't wobble sideways as it
  counts
- Shared components (`widgets/ui.dart`): `PillButton`, `RoundAction`,
  `InfoChip`, `SectionLabel`, all built on one `Pressable` that gives every
  control the same press-to-shrink feedback (`AnimatedScale`), a pointer
  cursor and keyboard activation (`FocusableActionDetector`), and a
  screen-reader label (`Semantics`)

## Listening feedback from amplitude alone (`SessionController._onAmplitude`)

The app only has loudness in real time — real pitch/chord/key detection
still happens after you stop (Basic Pitch isn't a streaming model here).
Two small, honest techniques get real-time *feel* without pretending to
detect more than loudness:

- **Peak (not beat) detection**: a rising edge above a loudness threshold
  (curved amplitude crossing up through ~0.5, not re-firing within a
  quarter second) is treated as "a hit" (`Scene.lastPeakAt`) — approximate,
  reactive to loudness, explicitly *not* a real beat grid
- **Silence as a signal**: tracking "seconds since the last loud sample"
  (`_lastLoudAt`) is enough to auto-stop a recording after it's gone quiet
  for 3 s (once it's at least 10 s long) — and the listening screen's hint
  line only mentions that once it's actually true
- The acoustic stream (`widgets/acoustic_stream.dart`) draws those same
  40 ms loudness samples as bars, averaged in groups of three — a
  depiction of what the mic actually heard, not a decorative equalizer

## The mascot (`widgets/mascot/`)

- Drawn to the reference sheet's measurements: the painter works in a
  fixed 220 × 200 "design box" whose numbers (body 84 × 142, eyes 18.5
  off-center, a three-stroke grille, a 52-radius stand arc) were measured
  off `Inpiration/Mascot States and Emotions Sheet.png`; `canvas.scale`
  maps that box onto whatever size the widget is. Change the size, the
  proportions can't drift
- A pure mood function (`mascot_mood.dart`): `moodFor(phase, now,
  hasError, lastTapAt, settleStart, playing, keyConfidence, ...)` returns
  one of the sheet's states. No canvas, no animation — so it's unit tested
  directly (`test/mascot_mood_test.dart`) and can only ever show a mood
  something real caused (an error → surprised, a clear key → excited, 30 s
  untouched → sleepy)
- Timestamps instead of animation controllers: each mood's motion
  (breathing, bouncing, swaying, notes drifting) is computed from
  `now` and `since` (seconds since the mood started). Switching mood swaps
  the eyes behind a 0.18 s blink, so changes feel organic rather than
  snapping
- `canvas.save()` / `translate` / `rotate` / `scale` / `restore()` —
  tilting and squashing the body around its *base* (so it leans in its
  cradle) by moving the origin there first, transforming, then moving
  back
- `canvas.drawArc` — the stand is an arc of a circle, a little more than
  a half circle so the tips curl up beside the body
- Reduce Motion: `MediaQuery.disableAnimations` makes the painter hold each
  mood's resting pose
- Programmatic audio synthesis (`scripts/generate_splash_chime.py`): a
  sine wave sampled at 44.1kHz, scaled to 16-bit PCM integers, and wrapped
  in a WAV header — the splash's three-note chime, which the mascot now
  "sings" along to (sleepy → singing → eyes open)

## The vocal contour (`widgets/contour/`)

- Layout as a pure, tested class (`ContourLayout`): time → x, MIDI pitch
  → y, note → pill rectangle, tap point → note. The painter and the tap
  handler both use it, so what you see and what you can tap can't disagree
- Fitting the pitch range to the notes (`note_range.dart`'s
  `fitPitchRange`) rather than the raw min/max, so one stray detection
  doesn't squash every other note into a thin band
- Density-aware labels: pills are widened to fit their note name only when
  every note can have one without overlapping (`pillFloor`); in a dense
  take the pills stay narrow and only the sounding note is labelled
- `Path.computeMetrics()` / `extractPath` — how the dashed melody thread
  is drawn: walk along the curve's length and draw every other short
  stretch
- `Curves.easeOutBack` — overshoots its target before settling; the notes
  "pop" into place one after another when results land

## The edge fluid field (`widgets/fluid_field.dart`)

A liquid/metaball-style background hugging the top and side edges of the
screen, approximating the look of a WebGL prototype (`Inpiration/
ferroflow_music.html`) without porting its fragment shader.

- **Why not a real fragment shader**: the prototype renders via a
  per-pixel GLSL loop over dozens of line-segment "spikes." This app has
  never used `dart:ui`'s `FragmentProgram`/`FragmentShader` and only runs
  via Flutter web (CanvasKit) — porting a nested, uniform-bound-loop GLSL
  shader into Skia's SkSL subset with no prior art in this codebase was
  judged more risk than it was worth for a visual that's explicitly meant
  to be tested and iterated on quickly
- **Two dead ends before landing on the field-math approach, both worth
  knowing about since they're easy to reach for again**:
  1. Many small blurred, additively-summed capsule shapes
     (`MaskFilter.blur` + `BlendMode.plus`), sharpened back with a
     contrast `ColorFilter.matrix` — chasing the prototype's metaball
     look by *rendering trick* rather than by its actual math. Failed
     silently: a Gaussian blur conserves *total* alpha but spreads it
     over an area roughly proportional to the blur radius squared, so a
     small or short shape's *peak* intensity drops fast as blur radius
     grows. At idle the spikes were short enough that blurring then
     thresholding them left literally nothing visible.
  2. One filled `Path` (screen edge as the outer boundary, a
     noise-driven wavy curve as the inner one) with a resting
     `MaskFilter.blur` left on for softness. This fixed visibility
     (a filled polygon is always visible, no threshold to tune) but
     looked wrong in a different way: a uniform hazy band, not distinct
     organic blobs — the blur was doing all the shape-defining work
     instead of the field math, so there was nothing underneath to
     actually look like liquid fingers.

  The shipped version keeps dead-end 2's *rendering* (one filled path,
  smoothed by a quadratic bezier through each pair of sample midpoints) but
  replaces *where the shape comes from*: [`fieldLengthAt`] sums the same
  `radius² / (distance² + 1)`-style falloff the prototype's shader sums
  per pixel, just once per rim sample instead of once per pixel — twelve
  Gaussian bumps (one per pitch-class position around the rim), each
  with its own independently-drifting amplitude, summed and passed
  through a saturating curve (`1 - exp(-sum * gain)`) so overlapping
  bumps blend into a taller, wider merged lobe instead of just adding
  past 1 and clipping flat. No blur anywhere — the organic, merging
  character comes entirely from the field summation; the only smoothing
  is the bezier interpolation between samples, for a crisp liquid edge
  rather than a soft glow
- **Arc-length, not angle, parameterization** for the rim the inner curve
  is measured from (`edgeAnchor`/`edgeInward`): the prototype places its
  12 spikes by angle around a full circle, which is fine when every
  angle is in play. Once the bottom of the screen is excluded, angle-
  slicing would bunch points at the two remaining corners; walking a
  fixed arc-length around the left-top-right rim instead keeps them
  evenly spaced
- **Tapering to a point at the bottom corners, not a flat cut**
  (`edgeTaper`): a first version stopped `edgeAnchor`/`edgeInward`
  themselves at `size.height * (1 - fluidBottomReserve)`, so the rim
  simply didn't exist below that line — visually an abrupt flat cut
  with a sharp corner where the band ended, which reads as a container,
  not a liquid. Now the rim runs the *entire* edge, all the way to the
  true bottom-left/bottom-right corners, and `edgeTaper` instead scales
  each point's *reach* down to 0 as it nears either end (eased with an
  exponent > 1 for a fuller, rounder taper rather than a thin wedge) —
  so the inner (wavy) boundary simply converges onto the outer boundary
  (the screen's own edge) right at the corner. There's no separate "end
  cap" to draw; the shape just naturally pinches to a point, the way a
  real drop of liquid running down an edge would thin out rather than
  stopping square
- **The header bar is fluid too** (`topInset`, `headerFill`): the painter
  fills a solid band across the top of the canvas and starts the field's
  own rim below it, so the bar and the walls are one shape with one
  gradient, not a bar sitting on top of a separate effect. During the
  intro the band's height eases from 0 to full (`headerFill`) — the
  liquid "pours" into the header — and the header's title and button
  only fade in once it's mostly full (`headerContentReveal`), so the
  fluid is what reveals them. Same pure `(scene, now)` style as the rest
  of the file: no new state, just one more function of the intro time
- **A small fillet at the top two corners** (`_topCornerRadius`, drawn
  via `quadraticBezierTo` the same way a rounded-rect corner is built):
  the only place the fluid's outer boundary still has to touch an
  actual geometric corner (where the screen's own top edge meets its
  sides) — even there, nothing about a fluid is a perfect right angle
- **The rim wraps, so distance must too**: `fieldLengthAt` measures each
  bump's distance from a sample point as
  `min((t - center).abs(), 1 - (t - center).abs())` — without the
  second term, positions near `t=0` and `t=1` (which are actually right
  next to each other, both near the bottom-of-left-edge/
  bottom-of-right-edge seam) would see each other as maximally far
  apart instead of adjacent, putting a visible seam where there
  shouldn't be one
- **Energy tied to live volume, continuously — two earlier attempts
  missed this**: version 1 drove every spike's amplitude from continuous
  noise the whole time, with no connection to the actual recording at
  all — "a generic wave throughout the fluid." Version 2 fixed that by
  keeping every spike at a calm floor until `Scene.lastPeakAt` fired (a
  discrete "loudness just crossed a threshold" event, the same signal
  already driving the mascot's listening bob), at which point one
  randomly-chosen spike got a pronounced rise-then-decay pulse — tied to
  the recording, but still read as an isolated blip: a held, sustained
  note should keep the fluid pulsating for as long as it's held, not
  fire once and go quiet. `_recordingAmplitude` now instead scales a
  continuous organic wave (the same "two unrelated sines multiplied"
  shape as `_idleAmplitude`, blended from two phase-shifted terms)
  directly by `liveVolume` — `Scene.live`'s own trailing average, the
  exact "how loud right now" signal the acoustic stream's "now" dot
  reads too (`liveVolume`, a shared top-level function in
  `session/scene.dart`, so both read the same number the same way). Held loud input keeps
  pulsating the whole time it's held and scales with its own loudness;
  quieter input pulses less; true silence (`liveVolume` at or near 0)
  locks every spike to an exact, motionless floor — not asymptotically
  approaching stillness, genuinely stagnant. Each spike's own phase
  offset still shifts independently over time, so which spikes are
  pulsing hardest at any instant keeps moving around the rim — that's
  where the "randomness in where" from the earlier version survives,
  now layered on a magnitude that's honestly driven by the audio rather
  than driving the whole effect by itself
- **Staggered entrance, reusing `Scene.introStart`**: rather than a new
  timestamp field, the fluid's grow-in reuses `Scene.introStart`/
  `introDuration`, set when the session screen first appears. Each rim point's growth is
  offset by a small, position-based stagger so the band rises unevenly
  around the rim (like liquid actually would) instead of every point
  snapping to life in lockstep

**Polish pass — droplets** (after you said the shipped version still
"looked cheap and unfinished," a first attempt also added a per-vertex
highlight mesh and a meniscus edge stroke via `Canvas.drawVertices` —
reverted in the same sitting after you looked at it and said it was
worse, not better; only the droplets below survived that pass):

- **Droplets reuse `Scene.lastPeakAt` as a pure trigger, decoupled from
  the shape itself**: the fluid's own shape is driven by the continuous,
  volume-scaled wave in `_recordingAmplitude` — there's no single
  "moment" left in that signal to spawn a one-off effect from. Rather
  than inventing new state, `activeDroplet` reuses `Scene.lastPeakAt`
  (a single timestamp, not a history — the same field the mascot's own
  peak bob already reads) purely to decide *when* to show one droplet,
  independent of how the fluid's own length is computed — a small
  example of one `Scene` field serving two unrelated, independently-
  tunable effects without coupling them together

**Staying on screen — settling instead of vanishing, note-wise playback
pulses** (you asked for the fluid to stay a recognizable, persistent part
of the app rather than something that only shows up while recording):

- **Reach, not opacity, is what "recedes"**: the fluid used to fade to
  fully transparent 0.5s into `Phase.analyzing` and stay invisible for
  `Phase.settled`. Fading alpha to 0 reads as the fluid *disappearing*;
  shrinking how far it's allowed to reach inward (`reachScale`) instead
  reads as it *settling back toward the edges* — the same shape-based
  idiom this file already uses everywhere else (`edgeTaper` shrinks
  reach near the bottom corners the same way), rather than introducing
  a second, unrelated "fade it out" mechanism just for phase changes
- **The settle easing rides on timing this codebase already has**:
  `reachScale` eases from full reach down to its smaller settled value
  over 0.6s from `Scene.analyzeStart`. `SessionController` already holds
  `Phase.analyzing` for at least ~1.6s (`_minAnalyzeSeconds`) before
  settling — both comfortably longer than that 0.6s — so by
  the time `Phase.settled` actually begins, the reach has already
  finished easing down with no special-casing needed for the hand-off
- **Pitch class *is* the rim position**: `_playbackAmplitude` doesn't
  need any new geometry to put "12 notes on 12 points of the fluid" —
  the file already has 12 evenly-spaced rim positions (one per spike),
  so pitch class `k` (0=C..11=B) just *is* spike index `k`, the same way
  the reference prototype maps pitch classes onto clock positions
  (`Inpiration/ferroflow_music.html`'s `slotOf`)
- **One "is this sounding" convention**: `scene.playingAll &&
  playhead != null && playhead >= note.startTime && playhead <=
  note.endTime`, the same test the contour uses to light a pill. Looping every note and taking the *max* envelope per pitch class means
  several simultaneously-sounding notes (a chord) each light up their
  own spike automatically — no separate chord-aware code path needed

**Making the playback pulses feel musical, not rigid** (after the first
version's pulses read as too big and too mechanically on/off):

- **A release phase that spills past the note's own boundary, on
  purpose**: the first version's envelope just stopped being considered
  the instant `playhead > note.endTime` — a real cutoff, not a fade.
  `_noteEnvelope` now keeps easing down for `_noteRelease` seconds
  *after* `endTime`, and the loop in `_playbackAmplitude` had to widen its own bound to match
  (`note.endTime + _noteRelease`) or the release tail would simply never
  be reached in the first place — the envelope and the code deciding
  whether to even evaluate it have to agree on where a note's influence
  actually ends
- **Easing curves as a stand-in for inertia, not a literal spring**: the
  reference prototype's own ripple physics (`step()` in `Inpiration/
  ferroflow_music.html`) is a real spring/damper integrator, which needs
  state carried across frames (position *and* velocity). Every function
  in this file is deliberately a pure function of `(t, now, scene)` with
  no history — adding a real spring would be the first exception to
  that. `Curves.easeOutCubic`/`easeInCubic` on the attack/release get
  most of the *feel* (gradual, never snapping) without that
  architectural jump; a genuine integrator is the fallback if easing
  curves alone don't read as weighty enough
- **A little per-note timing jitter reads as "alive"**: `_noteTimingJitter`
  (the same `sin(x)*43758.5453`-fraction hash this file already uses for
  `_hashedRimPosition`) nudges each note's own attack/release duration by
  ±15%, seeded off that note's `startTime` so it's stable rather than
  re-rolled every frame. Small, but it's the difference between every
  pop looking like a mechanically identical copy of the last one and
  each one landing with its own slightly different timing
- **A shared resting baseline removes a hidden snap**: `_playbackAmplitude`
  used to return a literal `0.0` for every spike the instant
  `scene.playingAll` was false→true (or the reverse), with only
  individual notes' own eased envelopes raising it back up — so the
  field's *resting* level itself silently depended on whether playback
  happened to be running, and pressing play (or playback finishing)
  changed it in one frame with no easing at all. It now always starts
  from the same `_idleAmplitude` ripple idle/analyzing already use,
  whether or not anything is playing, with a sounding note's envelope
  only ever raising a spike *above* that shared floor via `math.max` —
  nothing left to snap, because both sides of the flip already agree on
  the resting value

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

## Suggesting chords for a melody: the harmoniser (`backend/app/harmoniser/`)

The heart of the app. A hummed tune has no chords in it to *detect*; the
job is to *suggest* chords that fit. Nothing here is a trained model: it's
music theory written as scoring rules, a table of habits counted from a
chord corpus, and a search. That keeps every suggestion explainable.

- **One melody line** (`melody.py`): Basic Pitch reports every note it
  hears. The "skyline" keeps, at each moment, the highest sounding note,
  merges repeats and drops blips under 80 ms. The same file routes a take
  as melody / polyphonic / full mix by how many notes sound at once.
- **A beat grid** (`timing.py`): bars and beats so the engine knows which
  notes fall on strong beats. With the app's click it's exact; otherwise
  tempo comes from an onset *tempogram* (librosa's autocorrelation of
  "when notes start"), and beat 1 from phrasing: a note right after a long
  note or rest usually starts a phrase, and phrases start on beat 1.
  Metric strength: beat 1 > beat 3 > beats 2 and 4 > off-beats.
- **The Krumhansl-Schmuckler key** — correlating the melody's
  pitch-class weights against measured "key profiles" (via `music21`),
  here weighted by note length × beat strength, with the runner-up kept.
- **How a note sits under a chord** (`scoring.classify`): a *chord tone*
  (full credit), *colour* (a 9th/13th/11th: partial credit, more on a
  seventh chord than a plain triad), a *passing/neighbour* note (moves by
  step, not on beat 1: half credit, it's explained by the line), or a
  *clash* (a long or strong-beat note outside the chord: a penalty).
- **The score of a whole progression**: melody fit + key fit (out-of-key
  chords cost more) + a corpus prior (how natural the move is) + root
  motion (down a fifth is the strongest pull) + cadences (V→I or IV→I at
  a phrase end) + a penalty for sitting on one chord too long.
- **Beam search** (`search.py`): trying every progression is impossible
  (dozens of chords per bar, many bars), so the search keeps only the best
  ~60 partial progressions after each bar and extends those. Safe and
  Colourful are the same search with different weights ("profiles");
  Surprising is Safe plus one or two out-of-key turns that still fit the
  melody and resolve properly (a secondary dominant should land on its
  target, a fifth below).
- **An n-gram corpus prior** (`prior.py`, `scripts/build_progression_prior.py`):
  676k songs from the Chordonomicon corpus, each section's chords turned
  into key-relative tokens ("7:maj" is V in any key) and counted as
  unigrams/bigrams/trigrams. Asking P(next | previous two) uses *backoff*:
  trust the trigram when there's enough evidence, otherwise the bigram,
  otherwise how common the chord is overall. It judges chord *families*
  (V vs V7 count as one), since chord sheets often drop the 7, and it's
  *blended* 50/50 with textbook functional harmony, because the corpus is
  mostly pop and would otherwise turn every folk tune into I–IV–I loops.
  (Chordonomicon is CC BY-NC: fine for this project, not for selling it.)
- **Holding vs moving**: chord corpora list *changes*, not held bars, so
  a held chord can't be judged by them; it gets a neutral value instead,
  and repetition rules decide when holding has gone on too long.
- **Reasons from the score** (`reasons.py`): each chord's two biggest
  score terms become sentences ("Your long G becomes the 9th over F"), so
  an explanation is always true of the choice rather than invented to
  justify it. Roman numerals and functions (tonic / predominant /
  dominant, secondary dominants, borrowed chords) come from `vocab.py`.

## Getting the timing right (`backend/app/onset.py`, `timing.py`)

- **Where the music starts** (`onset.music_start_samples`): people press
  record, then breathe or settle the phone, and Basic Pitch hears that
  lead-in's mains hum as confident-looking low notes, which then became
  the melody's first note and dragged the beat grid and first chord into
  the silence. The fix finds the first moment clearly louder than the
  recording's own background (above a 70 Hz high-pass, where hum lives)
  that *stays* up for 0.12 s (so a tap isn't music), and drops notes
  before it. Melody notes below E2 also need high confidence: nobody
  sings that low.
- **The background is the quietest stretch, not a percentile.** A first
  version used the 10th percentile of the whole clip as the background,
  which works on a 4-second test but misses a 2-second lead-in in a
  90-second song (2% of the frames, so the percentile lands inside the
  music). A lightly smoothed minimum doesn't care how long the song is.
- **Windowed energy with a cumulative sum**: the energy of every window
  is `c[i+frame] − c[i]` on one running sum of squares, O(N), instead of
  building a frames × window matrix (which took ~330 MB and 3 s for 90 s
  of audio; this takes ~0.05 s).
- **Refining the tempo**: the tempogram is usually a percent or two out,
  and over a 20-second take that slides the bar lines a whole beat off
  the tune. Tempo (±5%) and beat phase are now searched *together* for
  the pair that puts the most note weight on beats, in one vectorised
  numpy grid (periods × phases × notes).
- **3/4 or 4/4** (`timing._detect_meter`): long notes and phrase starts
  recur every bar, so the per-beat accent pattern correlates with itself
  at a lag of one bar — 3 beats for a waltz, 4 for almost everything else
  (autocorrelation). Only detected when no click was used.
- **Not blocking the server** (`main.py`): FastAPI runs `async def`
  handlers on one event loop; heavy CPU/GPU work inside one freezes every
  other request (job polling included) until it finishes.
  `run_in_threadpool` moves the work to a worker thread so the loop stays
  free.
- **Don't do work twice**: one upload used to be loaded from disk four
  times and transcribed twice, and harmonised even when the result was
  about to be replaced. Now the audio is loaded once for both
  measurements, Basic Pitch's notes are passed along, and a song's first
  answer skips alternatives its background job recomputes from the vocals
  anyway (first answer ~10 s → ~6 s).

## An LLM proposes, the engine decides (`backend/app/llm.py`)

- The Bold option comes from Gemini: it gets a compact, factual summary of
  the tune (notes per bar, strong beats, phrase ends) and proposes
  adventurous progressions in Roman numerals, as JSON.
- **Validation**: every proposal is parsed into the engine's chord
  vocabulary (a regex Roman-numeral parser, `vocab.parse_roman`) and scored
  with the same terms as the others; any chord that clashes with a long or
  strong-beat note gets the whole proposal rejected.
- **Grounded explanation**: a second call gets only the engine's verified
  facts about each chord (which melody notes are chord tones or colour,
  its function, how rare it is in the corpus) and writes the "why" in the
  companion's voice — so the LLM supplies taste and words, never facts.
- **Graceful fallback**: no `GEMINI_API_KEY` (read from `backend/.env`,
  gitignored), a timeout, or nothing valid → the corpus option is used.
  The engine is tested with a stubbed client, so the tests never call Google.
- Plain `urllib` with JSON in/out rather than an SDK: one less dependency
  for two HTTP calls.

## Hearing the chords under your take (`backend/app/synth.py`, `SessionController`)

- **Additive synthesis**: each chord is a few sine-based voices (plus two
  overtones for warmth) in close position around middle C and a bass root
  below, each with a soft attack and a release that overlaps the next
  chord so changes don't click; rendered to WAV by `/backing`.
- **Two players in sync**: the take and the backing are separate
  `AudioPlayer`s; every play, pause, seek and loop moves both to the same
  position. Simple, and close enough for short takes (no sample-accurate
  mixing needed).
- **A click for an exact grid**: an optional click (`scripts/generate_click.py`,
  under 30 ms and mostly noise, so if it leaks into the mic Basic Pitch
  drops it as a blip) plays on a `Timer` while recording; the first
  click's time is sent with the tempo, so the backend skips guessing.
- **Nudging without re-recording**: `/harmonise` takes the already
  transcribed melody plus an edited grid (beat 1 moved, tempo ×2 or ÷2,
  two chords per bar) and re-suggests in milliseconds.

## Key and chord detection from notes (`backend/app/harmony.py`, legacy)

The original approach: look up which chord the simultaneous notes spell.
It's the wrong model for a melody and fails on real songs (see the design
spec), so it's no longer used for suggestions; its pieces (overtone
removal, the Viterbi smoother) are kept for the song-recognition work.

- Pitch class / chroma vectors — collapsing notes to "which of the 12
  pitches is sounding," ignoring octave
- Chord template matching — scoring the chroma at each moment against a
  fixed set of chord shapes rather than recognising a chord as a learned
  pattern
- The Viterbi algorithm — dynamic programming over per-frame guesses to
  find the single most likely *path* through time, penalising rapid
  switching so a chord holds steady instead of flickering
- `music21` — the Python music-theory library doing key-profile
  correlation; worth skimming its docs to see what else it can do

## Recognising a song's own chords (`backend/app/songs/`)

For an uploaded song the question changes from "what would fit?" to "what
does it play?" — and the answer needs real audio models, not the note
lookup the app started with (a strummed chord ringing out produces few
note events; overtones produce fake ones; melody notes get counted as
chord tones).

- **Is it a song?** (`melody.classify_input`): the average number of
  notes sounding at once tells a single tune from chords, but not a piano
  from a band. The tie-breaker is drums: **HPSS** (harmonic-percussive
  source separation) splits a spectrogram into sustained tones
  (horizontal lines) and hits (vertical lines); a song with drums has a
  few percent of its energy in the percussive part, a hummed take or a
  solo instrument almost none.
- **Source separation (Demucs)**: a neural network that splits a mix into
  stems — drums, bass, "other" (guitars, keys) and vocals — so the melody
  comes from the vocal stem and the bass line from the bass stem instead
  of a tangle of everything.
- **Beat tracking (Beat This!)**: beats and downbeats from the audio, so
  chords can change on beats and bars have a real position.
- **Chord recognition (BTC)**: a transformer that looks at a
  **constant-Q transform** (a spectrogram whose bins are spaced like
  musical semitones: 24 per octave here) and outputs, ~11 times a second,
  a probability for each of 170 chords (12 roots × 14 qualities, plus
  "no chord").
- **Beat-synchronous decoding** (`decode.py`): BTC's frame-by-frame
  guesses flicker, so they're averaged over each beat and run through a
  **Viterbi decoder** (the same "best path through time" idea as the old
  chord smoother) whose rules are what a musician assumes: change chord
  only on beats and most readily on bar lines; the bass note is usually
  the root; some moves are far more likely than others (the corpus prior,
  in the song's key); holding is the default.
- **Confidence shown as confidence**: each recognised chord keeps how
  much of its beat's probability it had; unsure ones are drawn faded and
  marked "maybe" rather than shown as fact.
- **Background jobs** (`jobs.py`): the full song takes ~30 s, so `/analyze`
  answers at once from the top line and starts a job in a thread; the app
  polls `GET /jobs/{id}` for the stage ("Separating the instruments…")
  and swaps in the song's progression (the Original card) when it's done.
  Models load once, on the first song, so melody takes stay fast.
- **Pinned versions on purpose**: `requirements-songs.txt` pins torch and
  torchaudio to 2.6, because Demucs uses torchaudio functions newer
  releases removed — an example of a dependency's dependency setting your
  ceiling.

## What each instrument is doing (`backend/app/songs/roles.py`)

A song's transcription used to be one wall of every note. Now each
separated stem becomes a *part* with its own notes and a plain sentence
about its role, measured, not guessed:

- **Melody** — the share of its time on notes of the current chord
  (high: it sits "inside" the harmony; lower: passing and colour notes
  give it movement), and its range as the 5th–95th percentile of pitches
  so a few stray notes leaking into the vocal stem don't stretch it.
- **Bass** — how often its lowest note at a bar's first beat is the
  chord's root: usually high, because the bass is what tells your ear
  which chord you're on; lower means a walking line or inversions.
- **Harmony** (guitars, keys) — *how* it plays the chords, from how its
  notes start: many notes starting within 50 ms of each other = strummed
  block chords; one after another = arpeggios; few long notes = pads.
- **Drums** — hits per bar from the drum stem's *onset envelope* (how
  suddenly the sound gets louder), and whether the loudest hits fall on
  beats 2 and 4 (a backbeat) or on beat 1.
- **A real-data lesson**: the first drum count said "1 hit a bar". librosa
  scales the onset envelope to its single loudest moment, so one crash
  anywhere in 90 seconds pushed every ordinary hit under the threshold.
  Scaling to the 99th percentile instead (robust to a few outliers) found
  ~4 hits a second, matching what you hear. Percentiles instead of
  min/max is the same idea as the melody range above.
- **Soloing a part**: the stems are saved and served from
  `/jobs/{id}/stems/{name}`; choosing a lens in the app swaps the player to
  that stem's URL and seeks to the same position. The endpoint only
  accepts the four known stem names and an alphanumeric job id, so a
  request can't reach other files (no path traversal).

## Loading model weights safely (`backend/app/songs/btc.py`)

The song path uses pretrained models downloaded from other people's
repositories. How you load their files matters as much as what they do.

- **A `.pt` file is a pickle.** PyTorch saves checkpoints with Python's
  `pickle`, which can rebuild almost any object. To do that, a pickle can
  contain instructions like "import this module and call this function
  with these arguments" that run *while it loads*. A malicious file could
  ask for `os.system(...)` and it would run the moment you call
  `torch.load()`. Loading someone's pickle is like running their script.
- **`weights_only=True`** switches to a restricted loader that only
  rebuilds plain data: tensors (the weights themselves), numbers, strings,
  lists, dicts. Anything else the file asks for is refused with an error
  instead of executed. A trained model is just numbers, so a legitimate
  checkpoint loads fine; a booby-trapped one fails loudly. It's the
  default since PyTorch 2.6. `weights_only=False` is the old behaviour:
  only for files from a source you completely trust.
- **Allow-listing exactly what's needed.** BTC's checkpoint also stores the
  mean and standard deviation used to normalise its input, saved as numpy
  values. Those aren't on the default safe list, so
  `torch.serialization.safe_globals([...])` allows just the numpy functions
  that rebuild an array or a single number from its type and raw bytes —
  data, not code — under the names the file was saved with. When the
  first attempt hit one more numpy type (`scalar`), the loader stopped and
  said so: the safety net working as intended.
- **Checking the file is the one you reviewed.** `scripts/fetch_btc_weights.py`
  downloads the weights from BTC's repository at a *pinned commit* and
  compares their SHA-256 hash with the published one before saving;
  `btc.load()` checks it again. A changed or corrupted file is refused.
- **Reading the code you run.** Instead of importing the cloned research
  repo, the few hundred lines of model code were reviewed (plain PyTorch
  layers: no file, network or subprocess access) and vendored into the
  backend with their MIT licence, minus training code and an unsafe
  `yaml.load`. Layer *names* were kept exactly, because a checkpoint's
  weights are matched to the model by name (`load_state_dict`).
- Why this came up: the first attempt loaded BTC with
  `weights_only=False` straight from the cloned repo, and the session's
  safety check blocked it. That was a reasonable call for an unreviewed
  third-party file, and the steps above are the safe way to get the same
  result. Demucs and Beat This! didn't need this because their own
  libraries load their published weights.

## Testing

- `pytest` (`backend/tests/`) — the melody, grid, key, harmoniser, LLM
  validation and synth logic is tested directly on hand-written notes,
  without real audio or the ML model. `tests/melodies.py` writes
  public-domain tunes (Twinkle, Ode to Joy, Frère Jacques) as notes, and a
  "golden" test checks Safe agrees with what musicians would play on most
  bars
- `flutter test` (`app/test/`) — Dart model parsing (`Analysis.fromJson`
  and friends), the mascot's mood rules, the contour geometry and the
  fluid field math are all tested as plain functions, independent of any
  widget
- Rendering a screen in a widget test: pump the real widget tree around a
  fake controller, advance time with `tester.pump(duration)`, and save the
  frame with `matchesGoldenFile` (`--update-goldens`). Load the real fonts
  first with `FontLoader`, or every glyph renders as a box
- Red-green TDD — writing a test that fails for the right reason *before*
  writing the code that makes it pass

## Forward-looking (not built yet)

- **Zooming the contour** for long clips, and chord-by-chord comparison
  of the original progression with the alternatives
- **Style presets**: the corpus prior's blend and genre slices tuned per
  style (pop, folk, jazz)
- **Distinct scale/mode detection** — today "key" and "scale" are the same
  thing (major/minor only, via Krumhansl-Schmuckler); detecting modes
  (Dorian, Mixolydian, etc.) or non-diatonic scales would be a separate
  step
