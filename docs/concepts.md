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

## Listening feedback from amplitude alone (`session_screen.dart`'s amplitude listener)

The "Listen" beat wants the app to feel alive while recording, but today
the app only has loudness in real time — real pitch/chord/key detection
still happens after you stop (Basic Pitch isn't a streaming model here).
Two small, honest techniques get real-time *feel* without pretending to
detect more than loudness:

- **Peak (not beat) detection**: a rising edge above a loudness threshold
  (curved amplitude crossing up through ~0.5, not re-firing within its own
  bob duration) is treated as "a hit" and drives the mascot's bob —
  approximate, reactive to loudness, explicitly *not* a real beat grid
  (tempo/downbeats, the doc's own "Phase 1: Melody foundation" work).
  Cheap and immediate; shouldn't be confused with the real thing later.
- **Silence as a signal**: tracking "seconds since the last loud sample"
  (`_lastLoudAt`) is enough to auto-stop a recording after it's gone
  quiet for a while — no pitch detection needed, just the same amplitude
  stream already being read for the live line.

## Local persistence (`shared_preferences`, `session_screen.dart`)

- The app's first piece of state that survives a restart: a single
  boolean flag (`hasSeenFirstRunHint`) remembering whether the
  first-run hint line has already been shown, so it appears exactly
  once, ever, rather than every time the app opens
- `shared_preferences` — Flutter's standard package for small local
  key-value data (a handful of bools/strings/numbers), backed by each
  platform's own simple storage (e.g. `UserDefaults` on iOS,
  `SharedPreferences` on Android, `localStorage` on web). It's `async`
  (`SharedPreferences.getInstance()`) because reading platform storage
  isn't instant, unlike reading an in-memory field
- This is deliberately not the same tool a "save my recordings"
  feature would reach for later (that needs real files/a database, not
  a few flags) — matching the tool to the size of the problem

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

## The mascot (`widgets/mascot.dart`)

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
- `canvas.drawArc` — the mascot's stand (the base a handheld mic rests
  in) is just the bottom half of a circle: `startAngle: 0` (3 o'clock),
  `sweepAngle: pi`, which in Flutter's clockwise-from-positive-x
  convention traces exactly the bottom semicircle, no path-building
  needed
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

## The splash screen, the wake-up intro, and musical lines

- The lines are a *depiction*, not a trace. Two different depictions now
  live side by side in `score_canvas.dart`, used for different moments:
  `strokeMusicalLine` (1-3 ribbon-wobble strands, used for the idle line
  and the settled/post-analysis lines) and `strokeGaussianWave` (one
  soft, Gaussian-bump line, used for the recording-time line and shared
  with the splash screen — see below). Neither tries to represent
  `scene.live`'s history across the growing span the way an early
  version did (loud earlier, quiet now, visible left to right) — that
  still looked like a miniature waveform. The settled lines (after
  analysis) are the one place that *does* map real amplitude across the
  clip's actual duration, since at that point there's a real finished
  recording to represent, not just a live level
- `strokeMusicalLine`, a top-level function in `score_canvas.dart` rather
  than a method — deliberately, so it's usable outside `ScorePainter`
  too: 1-3 overlapping strands, each a handful of sampled points joined
  with a light quadratic smoothing (`Offset.lerp` through each pair's
  midpoint) rather than straight segments — the smoothing is what keeps
  a strand reading as a flowing curve instead of a faceted polyline,
  especially once real, somewhat noisy audio data is driving its
  amplitude. Summed sines per strand, each at a different, unrelated
  frequency and phase (the same "organic, never-quite-looping" trick
  already used for the ambient drift), are what make 3 strands read as
  independent flowing lines rather than one line traced three times
- `smoothedAmplitude`: averaging a handful of nearby envelope samples
  instead of reading one raw point. Live microphone amplitude arrives in
  coarse, un-smoothed 40ms chunks (see `_startRecording`'s
  `onAmplitudeChanged` listener) — sampling it directly made the line
  visibly jittery; a small moving-average window fixes that without
  needing to change how the amplitude itself is captured
- A fixed `LineColors` palette (`theme.dart`) rather than coloring the
  lines by detected harmony: an earlier version of this tried tying the
  color to `HarmonicColor`/the chord timeline, genuinely data-driven,
  but it was reverted in favor of matching the reference board's fixed
  purple/green/orange directly — a reminder that "more meaningfully
  data-driven" isn't automatically "better" if it drifts from the
  agreed visual reference
- **`strokeGaussianWave`, shared between the splash screen and the
  recording-time line** — the splash's line was built first, as its own
  bespoke inline code in `_SplashLinePainter`, and was genuinely the
  better-looking of the two techniques; the recording-time line (then 3
  `strokeMusicalLine` ribbon strands) was later rebuilt to use the
  splash's actual technique instead of a separately-evolved one that
  happened to look similar. The renderer (sum a list of Gaussian bumps —
  `rise * exp(-(dist²)/(2·sigma²))` per bump, evaluated at each sampled
  x, then quadratic-bezier-smoothed the same way `strokeMusicalLine`
  is) now lives once, in `score_canvas.dart`; each caller only supplies
  *where the bumps are and how tall*:
  - the splash screen's 3 bumps are onset-triggered — anchored at fixed
    x positions, each rising and falling once (`sin(pi · q)`) in time
    with one of the 3 notes in `assets/sounds/chime.wav`
  - the recording-time line's 2-3 bumps are continuous instead — their
    x-position drifts slowly (the same "two unrelated sines" trick used
    everywhere else in this app) and their height is scaled directly by
    `liveVolume` (`Scene.live`'s trailing average, the same "how loud
    right now" signal the edge fluid field's recording pulse already
    uses) — loud input reads as pronounced, organically-drifting crests
    and troughs; a quiet room reads as a nearly flat line. Still not
    trying to trace the actual waveform shape, same as every other
    "depiction" in this file — only the *height* is data-driven
  - `reveal` (0..1, clips to a growing prefix from `x0`) is the one
    parameter both call sites actually use the same way: the splash
    plays it forward then backward (`Curves.easeOutCubic` then
    `easeInCubic`, the literal reverse of growing in) so the screen is
    blank again right before the cut to the home screen; the
    recording-time line doesn't need it at all (its own `x1` already
    grows as more gets recorded), so it just leaves `reveal` at its
    default `1.0`
- The home screen's *returning* line
  (`ScorePainter._introReveal`, driven by `Scene.introStart`) is a
  separate thing from the splash's line — it's `strokeMusicalLine`'s own
  `reveal` parameter, not `strokeGaussianWave`'s, even though both
  parameters mean the same "clip to a growing prefix" thing and both
  ultimately trace back to the splash screen's original grow-in idea
- `Scene.introStart` — one more timestamp in the same family as
  `settleStart`/`analyzeStart`, set once in `SessionScreen.initState`
  and read as `now - introStart` wherever the one-time "waking up"
  sequence needs to animate and then stop (the mascot's grow-and-blink
  in `mascot.dart`, then the line's `reveal` picking up right after)

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
  smoothed with `strokeMusicalLine`'s quadratic-bezier technique) but
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
  exact "how loud right now" signal the recording-time musical lines
  already swell with (`liveVolume` was promoted from a `ScorePainter`-
  private method to a shared top-level function in this file so both
  callers read the same number the same way). Held loud input keeps
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
  timestamp field, the fluid's grow-in reuses the same `introStart`/
  `introDuration` the mascot's wake-in and the line's `reveal` already
  use, so all three land in the same window. Each rim point's growth is
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
  over 0.6s from `Scene.analyzeStart`. `_stopRecording` already holds
  `Phase.analyzing` for at least ~1.6s (`minListen`) and `_replay` for
  1.4s before settling — both comfortably longer than that 0.6s — so by
  the time `Phase.settled` actually begins, the reach has already
  finished easing down with no special-casing needed for the hand-off
- **Pitch class *is* the rim position**: `_playbackAmplitude` doesn't
  need any new geometry to put "12 notes on 12 points of the fluid" —
  the file already has 12 evenly-spaced rim positions (one per spike),
  so pitch class `k` (0=C..11=B) just *is* spike index `k`, the same way
  the reference prototype maps pitch classes onto clock positions
  (`Inpiration/ferroflow_music.html`'s `slotOf`)
- **Reusing the "is this sounding" convention `ScorePainter` already
  has**, rather than inventing a second one: `scene.playingAll &&
  playhead != null && playhead >= note.startTime && playhead <=
  note.endTime` is copied verbatim from `_paintNotes`/`_paintChords`.
  Looping every note and taking the *max* envelope per pitch class means
  several simultaneously-sounding notes (a chord) each light up their
  own spike automatically — no separate chord-aware code path needed

**Making the playback pulses feel musical, not rigid** (after the first
version's pulses read as too big and too mechanically on/off):

- **A release phase that spills past the note's own boundary, on
  purpose**: the first version's envelope just stopped being considered
  the instant `playhead > note.endTime` — a real cutoff, not a fade.
  `_noteEnvelope` now keeps easing down for `_noteRelease` seconds
  *after* `endTime`, and the loop in `_playbackAmplitude` (and
  `activeNoteBubbles`) had to widen its own bound to match
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
- **Note-name bubbles fade with the same envelope that drives the
  pulse**: `activeNoteBubbles` returns each currently-labelable pitch
  class's loudest matching note *and* that note's own envelope value, so
  `_paintNoteBubble`'s alpha is driven by the identical number shaping
  the fluid's bump — the label and the bump always appear and disappear
  in lockstep, rather than the label using its own separate fade timer
  that could drift out of sync
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
