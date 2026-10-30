import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../models/note.dart';
import '../theme.dart';
import 'score_canvas.dart' show Phase, Scene, introDuration, liveVolume;

/// Roughly how much of the screen's height, measured from the bottom, the
/// fluid tapers down to nothing within — not a hard cutoff (see
/// [edgeTaper]), so there's no sharp edge where it stops: it narrows to a
/// natural point right at the bottom-left/bottom-right corners instead,
/// leaving that area clear for a future tab bar as a side effect of the
/// taper rather than a drawn boundary.
const fluidBottomReserve = 0.18;

/// How many points are sampled around the rim to build the fluid's wavy
/// inner edge — high enough that the smoothed curve (see [FluidFieldPainter
/// .paint]) reads as flowing, not faceted.
const _rimSamples = 180;

/// How far inward the fluid can reach, as a fraction of the canvas's
/// shorter side.
const _maxLenFraction = 0.34;

/// One "finger" per pitch-class position around the rim, same as the
/// reference prototype's 12 anchors.
const _spikeCount = 12;

/// How wide each finger's bump is, as a fraction of the whole rim's
/// arc-length (0..1) — narrow enough that neighboring fingers read as
/// distinct pokes at rest, wide enough that they visibly merge once their
/// amplitude grows.
const _spikeWidthT = 0.034;

/// A small always-present floor so the rim never shows a literal gap
/// between fingers, even at their quietest.
const _ambientFloor = 0.05;

/// How quickly the summed field saturates toward a full-strength fill —
/// see [fieldLengthAt].
const _saturationGain = 1.7;

const _fillAlpha = 0.94;

/// How sharply the taper narrows toward each bottom corner — above 1 gives
/// a fuller, more rounded droplet-like tip rather than a thin wedge.
const _taperExponent = 1.6;

/// Radius of the gentle fillet at the two top corners — a fluid has no
/// perfect right angles, even where its outer edge follows the screen's
/// own corner.
const _topCornerRadius = 28.0;

/// A point on the fluid's rim — the full left-edge/top-edge/right-edge
/// perimeter, all the way down to the true bottom-left and bottom-right
/// corners — for arc-length position [t] (0..1). Arc-length, not angle,
/// parameterization: slicing by angle bunches points at the corners once
/// the bottom edge is excluded, arc-length doesn't.
Offset edgeAnchor(double t, Size size) {
  final leftLen = size.height, topLen = size.width, rightLen = size.height;
  final total = leftLen + topLen + rightLen;
  if (total <= 0) return Offset.zero;
  final d = t.clamp(0.0, 1.0) * total;
  if (d < leftLen) return Offset(0, size.height - d);
  if (d < leftLen + topLen) return Offset(d - leftLen, 0);
  return Offset(size.width, d - leftLen - topLen);
}

/// The direction the fluid grows inward at rim position [t] — trivial per
/// edge (no trig needed, unlike a generic rectangle-ray cast) since the rim
/// is only ever one of three straight edges.
Offset edgeInward(double t, Size size) {
  final leftLen = size.height, topLen = size.width;
  final total = leftLen + topLen + size.height;
  final d = t.clamp(0.0, 1.0) * total;
  if (d < leftLen) return const Offset(1, 0);
  if (d < leftLen + topLen) return const Offset(0, 1);
  return const Offset(-1, 0);
}

/// 0..1: how much of the fluid's full reach is available at rim position
/// [t] — 0 right at the two bottom corners (t=0, t=1), ramping up to 1
/// within [fluidBottomReserve]'s worth of arc-length and staying there
/// through the top and most of the sides. Multiplying a spike's length by
/// this is what turns an abrupt flat cutoff into a natural taper to a
/// point exactly at each bottom corner — there's no separate "end cap" to
/// draw, because the inner boundary simply converges to the outer one
/// (the screen's own edge) as the taper reaches 0.
double edgeTaper(double t, Size size) {
  final total = size.width + 2 * size.height;
  if (total <= 0) return 1.0;
  final tail = (size.height * fluidBottomReserve) / total;
  if (tail <= 0) return 1.0;
  if (t < tail) return math.pow(t / tail, _taperExponent).toDouble();
  if (t > 1 - tail) return math.pow((1 - t) / tail, _taperExponent).toDouble();
  return 1.0;
}

/// Two unrelated sine frequencies multiplied — the same "organic,
/// never-quite-looping" trick already used throughout this app
/// (`ribbonWobbleY`). [x] plays the role `f` plays there: a spatial seed so
/// each spike's amplitude drifts independently rather than in lockstep.
double _ripple(double x, double now) =>
    0.5 + 0.5 * math.sin(now * 1.7 + x * 2.31) * math.sin(now * 0.73 + x * 1.13);

/// 0..1 how strongly spike [k] is reaching out at rest (idle, or fading out
/// while analyzing) — a low, slow simmer with no connection to audio, since
/// there isn't any yet.
double _idleAmplitude(int k, double now) =>
    (0.14 + 0.10 * _ripple(k * 3.1, now * 0.25)).clamp(0.0, 1.0);

const _restingFloor = 0.08;

/// Below this trailing volume, the recording reads as silence — amplitude
/// locks to exactly [_restingFloor] with no time-variation at all, so the
/// fluid goes completely stagnant rather than asymptotically approaching
/// stillness.
const _silenceThreshold = 0.01;

/// 0..1 how strongly spike [k] is reaching out while recording. An earlier
/// version triggered one discrete, randomly-placed pulse each time a loud
/// moment crossed a threshold (`Scene.lastPeakAt`) — closer to the real
/// recording than pure noise, but it still read as an isolated blip rather
/// than something a held, sustained note would produce: a steady tone
/// should keep the fluid pulsating the whole time it's held, scaling with
/// its own loudness, not fire once and go quiet again. This version
/// instead scales a continuous organic wave (the same "two unrelated sines
/// multiplied" trick as `_idleAmplitude`, just two terms blended for a
/// richer shape) directly by [liveVolume] — [Scene.live]'s own trailing
/// average, the same "how loud right now" signal the recording-time
/// musical lines already swell with. Held loud input keeps pulsating for
/// as long as it's held; quieter input pulses less; true silence collapses
/// to a flat, motionless floor. Which spikes happen to be pulsing hardest
/// at any instant still shifts continuously around the rim (each spike's
/// own phase offset, `k * 3.1`/`k * 7.7`, is different) — that's the
/// "randomness in where," now layered on top of a magnitude that's
/// honestly tied to the audio rather than driving the whole thing.
double _recordingAmplitude(int k, double now, Scene scene) {
  final volume = liveVolume(scene.live);
  if (volume <= _silenceThreshold) return _restingFloor;
  final wave = _ripple(k * 3.1, now * 1.1);
  final wave2 = _ripple(k * 7.7 + 11, now * 2.3);
  final shape = 0.6 * wave + 0.4 * wave2;
  return (_restingFloor + volume * (0.3 + 0.7 * shape)).clamp(0.0, 1.0);
}

/// 0..1 how far inward the fluid reaches at rim position [t] — the same
/// `radius² / (distance² + 1)` falloff the reference prototype's fragment
/// shader sums per spike (see `Inpiration/ferroflow_music.html`'s field
/// function), just evaluated once per rim sample instead of once per pixel:
/// [_spikeCount] Gaussian bumps, one per pitch-class position, each with
/// its own amplitude (see [_recordingAmplitude]/[_playbackAmplitude]/
/// [_idleAmplitude], one per phase), summed
/// and passed through a saturating curve so overlapping bumps blend into a
/// taller, wider merged lobe instead of just adding past 1 and clipping —
/// the same "fingers merge when close" character metaballs have, without
/// needing an actual 2D implicit-field threshold search.
double fieldLengthAt(double t, double now, Scene scene) {
  var sum = _ambientFloor;
  for (var k = 0; k < _spikeCount; k++) {
    final center = k / _spikeCount;
    var dt = (t - center).abs();
    dt = math.min(dt, 1 - dt); // the rim wraps around, so distance wraps too
    final amp = switch (scene.phase) {
      Phase.recording => _recordingAmplitude(k, now, scene),
      Phase.settled => _playbackAmplitude(k, now, scene),
      Phase.idle || Phase.analyzing => _idleAmplitude(k, now),
    };
    sum += amp * math.exp(-(dt * dt) / (2 * _spikeWidthT * _spikeWidthT));
  }
  return (1 - math.exp(-sum * _saturationGain)).clamp(0.0, 1.0);
}

const _settledReachScale = 0.58;
const _settleDuration = 0.6;

/// How far inward the fluid is *allowed* to reach right now, as a
/// fraction of its normal full reach — 1.0 at idle/recording, easing down
/// to [_settledReachScale] over [_settleDuration] once analyzing starts,
/// staying there once settled. This is what makes the fluid "settle back
/// to the edges" when the user stops recording rather than disappearing:
/// an earlier version faded it to fully transparent here instead, which
/// read as the fluid vanishing rather than remaining a persistent part of
/// the screen. It also keeps the fluid out of the way once notes/chords
/// are on screen (`ScorePainter`'s own content lives in the same central
/// area) without a separate, redundant "is there room" check.
double reachScale(Scene scene, double now) {
  switch (scene.phase) {
    case Phase.idle:
    case Phase.recording:
      return 1.0;
    case Phase.analyzing:
      final start = scene.analyzeStart;
      if (start == null) return _settledReachScale;
      final t = ((now - start) / _settleDuration).clamp(0.0, 1.0);
      return 1.0 + (_settledReachScale - 1.0) * Curves.easeOutCubic.transform(t);
    case Phase.settled:
      return _settledReachScale;
  }
}

const _noteAttack = 0.22; // seconds, in audio/playhead time, not clock time
const _noteRelease = 0.4; // seconds of fade-out *after* a note's own endTime
const _playbackActiveAmplitude = 0.62;

/// A small, stable per-note timing variation (0.85..1.15), seeded off the
/// note's own start time so it's the same every frame rather than
/// re-rolled — different notes land with very slightly different
/// attack/release timing instead of every pop feeling like a mechanically
/// identical copy of the last one. The same hash trick already used for
/// `_hashedRimPosition`.
double _noteTimingJitter(double seed) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return 0.85 + 0.3 * (x - x.floorToDouble());
}

/// 0..1: how present a note reads as of [playhead] — a gentle eased rise
/// over [_noteAttack], holding at full strength while the note sounds,
/// then an eased *release* that keeps fading for [_noteRelease] seconds
/// past the note's own [noteEnd] rather than cutting the instant the note
/// technically ends. An earlier version snapped straight to "on" over a
/// much quicker 0.1s and had no release at all (the caller simply
/// stopped considering the note once `playhead > noteEnd`) — the pop read
/// as rigid, not musical. Easing both ends, and letting the tail spill a
/// little past the note's literal boundary, is what gives the pulse a
/// sense of weight/inertia without needing an actual spring simulation
/// (see the class doc comment's note on that trade-off).
double _noteEnvelope(double playhead, double noteStart, double noteEnd) {
  final jitter = _noteTimingJitter(noteStart);
  if (playhead < noteStart) return 0.0;
  if (playhead <= noteEnd) {
    final since = playhead - noteStart;
    final attack = _noteAttack * jitter;
    return since < attack ? Curves.easeOutCubic.transform(since / attack) : 1.0;
  }
  final release = _noteRelease * jitter;
  final sinceEnd = playhead - noteEnd;
  if (sinceEnd >= release) return 0.0;
  return 1.0 - Curves.easeInCubic.transform(sinceEnd / release);
}

/// 0..1 how strongly spike [k] is reaching out while settled (replaying
/// the finished recording). [k] *is* the pitch class (0=C..11=B) — the
/// same 12 evenly-spaced rim positions this file already has for every
/// other phase, mapped the way the reference prototype maps pitch classes
/// onto clock positions (`Inpiration/ferroflow_music.html`'s `slotOf`),
/// just adapted to this file's rim instead of a full circle. Mirrors the
/// "is this currently sounding" convention `ScorePainter._paintNotes`/
/// `_paintChords` already use (`scene.playingAll && playhead != null &&
/// playhead >= note.startTime && playhead <= note.endTime`), just widened
/// past `endTime` by [_noteRelease] so the release tail in [_noteEnvelope]
/// actually gets to play out instead of being cut off by this loop first.
/// Looping every note and taking the max per pitch class means multiple
/// simultaneously-sounding notes (a chord) each light up their own spike
/// for free — no separate chord-handling needed.
///
/// Starts from the same calm `_idleAmplitude` ripple idle/analyzing
/// already use *unconditionally* — not just as a fallback for when
/// nothing is playing — with any sounding note only ever raising a spike
/// *above* that baseline via `math.max`, never replacing it. An earlier
/// version started from a literal `0.0` whenever `playingAll` was true,
/// which meant the *entire* field's resting level silently depended on
/// whether playback happened to be running: the instant play was
/// pressed (or playback finished/stopped), every spike's baseline
/// snapped between the idle ripple and flat zero in a single frame, even
/// though nothing about that moment was supposed to be the dramatic
/// part — the notes' own eased attacks were doing the dramatic part
/// already. Keeping the baseline identical on both sides of that flip
/// means there's nothing left to snap.
double _playbackAmplitude(int k, double now, Scene scene) {
  final base = _idleAmplitude(k, now);
  final playhead = scene.playhead;
  if (!scene.playingAll || playhead == null) return base;
  var amp = base;
  for (final note in scene.notes) {
    final pc = ((note.midiPitch % 12) + 12) % 12;
    if (pc != k || playhead < note.startTime || playhead > note.endTime + _noteRelease) continue;
    amp = math.max(
      amp,
      _playbackActiveAmplitude * _noteEnvelope(playhead, note.startTime, note.endTime),
    );
  }
  return amp.clamp(0.0, 1.0);
}

const _bubbleThreshold = 0.4;

/// Which pitch classes currently have a note sounding strongly enough to
/// label with its name, which actual note to show (the loudest match —
/// a chord voiced across octaves shares a pitch class but only needs one
/// label), and that note's own current envelope (so a caller can fade the
/// label in/out exactly in step with the pulse it's labeling, rather than
/// popping it in/out abruptly). Empty outside active playback.
List<({int pitchClass, Note note, double envelope})> activeNoteBubbles(Scene scene) {
  final playhead = scene.playhead;
  if (scene.phase != Phase.settled || !scene.playingAll || playhead == null) return const [];
  final best = <int, ({Note note, double envelope})>{};
  for (final note in scene.notes) {
    if (playhead < note.startTime || playhead > note.endTime + _noteRelease) continue;
    final env = _noteEnvelope(playhead, note.startTime, note.endTime);
    if (env < _bubbleThreshold) continue;
    final pc = ((note.midiPitch % 12) + 12) % 12;
    final current = best[pc];
    if (current == null || env > current.envelope) best[pc] = (note: note, envelope: env);
  }
  return [
    for (final e in best.entries) (pitchClass: e.key, note: e.value.note, envelope: e.value.envelope),
  ];
}

/// 0 before rim position [t] has started growing in, 1 once fully grown.
/// [t] staggers each point's own growth across a small span of
/// [introDuration] so the fluid reads as flowing in around the rim from one
/// side, like liquid actually would, rather than every point snapping to
/// life in lockstep.
double _entranceGrowthAt(double now, double? introStart, double t) {
  if (introStart == null) return 1.0;
  const staggerSpan = 0.5;
  final staggerOffset = t * staggerSpan;
  final local = ((now - introStart - staggerOffset) / (introDuration - staggerSpan))
      .clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(local);
}

/// A pseudo-random rim position (0..1) for a discrete event timestamp —
/// the classic "hash a float through a scaled sine's fractional part"
/// trick: the *same* [seed] always maps to the *same* position (so a
/// droplet's launch point doesn't change mid-flight), while unrelated
/// seeds land on unrelated positions.
double _hashedRimPosition(double seed) {
  final x = math.sin(seed * 78.233) * 43758.5453;
  return (x - x.floorToDouble()).abs();
}

const _dropletDuration = 0.65;

/// The current droplet's position and progress (0..1 — 0 at launch, 1 once
/// it's fully faded), or `null` if none is in flight right now. Purely
/// derived from `now - scene.lastPeakAt`: no accumulated state, no new
/// `Scene` field, at most one droplet in flight at a time — exactly what
/// `lastPeakAt` (a single timestamp, not a history) already supports. A
/// pure spawn *trigger*, decoupled from the continuous volume-driven wave
/// that actually shapes the fluid (see `_recordingAmplitude`) —
/// `Scene.lastPeakAt` still fires on the same loudness-rising-edge signal
/// the mascot's own peak bob already reacts to.
({Offset position, double progress})? activeDroplet(double now, Scene scene, Size size) {
  if (scene.phase != Phase.recording) return null;
  final peakAt = scene.lastPeakAt;
  if (peakAt == null) return null;
  final t = (now - peakAt) / _dropletDuration;
  if (t < 0 || t > 1) return null;
  final rimT = _hashedRimPosition(peakAt);
  final anchor = edgeAnchor(rimT, size);
  final inward = edgeInward(rimT, size);
  final maxLen = math.min(size.width, size.height) * _maxLenFraction;
  final travel = maxLen * (0.5 + 0.9 * Curves.easeOut.transform(t));
  return (position: anchor + inward * travel, progress: t);
}

/// A small floating name tag for a currently-pulsing note — "the
/// significance of the pop," so a bump reads as a specific note rather
/// than an unexplained wobble. Styled as the same paper pill + soft
/// shadow language already used elsewhere in this app (`_QuietButton` in
/// `session_screen.dart`, the chord tabs in `ScorePainter._paintChords`)
/// rather than inventing a new one. [envelope] (from [activeNoteBubbles])
/// drives its alpha directly, so it fades in and out exactly in step with
/// the pulse it's labeling instead of popping in/out abruptly.
void _paintNoteBubble(Canvas canvas, Offset center, String label, double envelope) {
  if (envelope <= 0.01) return;
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Palette.ink.withValues(alpha: 0.85 * envelope),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final rect = Rect.fromCenter(center: center, width: painter.width + 16, height: 20);
  final shape = RRect.fromRectAndRadius(rect, const Radius.circular(10));

  canvas.drawRRect(
    shape.shift(const Offset(0, 1.5)),
    Paint()
      ..color = Palette.ink.withValues(alpha: 0.08 * envelope)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawRRect(shape, Paint()..color = Palette.paper.withValues(alpha: 0.95 * envelope));
  canvas.drawRRect(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = FluidColors.deepPurple.withValues(alpha: 0.35 * envelope),
  );
  painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
}

/// A liquid/metaball-style field hugging the top and side edges of the
/// screen, tapering to a natural point at the bottom-left/bottom-right
/// corners rather than stopping with a flat cut — approximating the look
/// of `Inpiration/ferroflow_music.html` without porting its per-pixel
/// fragment shader (this app has no shader infrastructure and runs on
/// Flutter web only, see docs/concepts.md).
///
/// Earlier versions of this painter tried to get the metaball look from
/// *rendering* tricks — first a blurred, additively-summed blend sharpened
/// with a contrast filter (small shapes lost too much mass to the blur and
/// vanished), then a single filled shape with a generic noise-driven wavy
/// edge softened by a blur (visible, but read as one hazy band, not
/// distinct organic fingers, and stopped with an abrupt flat cut rather
/// than tapering into the screen's corners). This version gets the organic
/// look from the same *field math* the prototype uses ([fieldLengthAt]) and
/// draws the result as one crisp filled path with no blur at all, its
/// outer boundary running the full rim (with a small fillet at the two top
/// corners — nothing about a fluid is a perfect right angle) and its inner
/// boundary tapering smoothly to meet that outer edge right at the bottom
/// corners (see [edgeTaper]).
///
/// Timestamp-driven off [clock], like every other painter in this app — no
/// `AnimationController`. Reads only [Scene.phase]/[Scene.introStart]/
/// [Scene.analyzeStart]/[Scene.live]/[Scene.lastPeakAt]/[Scene.notes]/
/// [Scene.playhead]/[Scene.playingAll]; no new `Scene` fields needed.
///
/// On "inertia": [_noteEnvelope]'s eased attack/release is a deliberate
/// stand-in for a real spring/damper (the reference prototype's own
/// `step()` function *is* a literal spring integrator) — a true spring
/// needs state carried from the previous frame (position *and*
/// velocity), which would make it the first stateful, frame-accumulating
/// piece of logic in this file, unlike everything else here, which is a
/// pure function of `(t, now, scene)`. Shaped easing curves get most of
/// the *feel* of weight/momentum without that architectural jump; if it
/// still reads as too mechanical, a real integrator is the next step up.
class FluidFieldPainter extends CustomPainter {
  FluidFieldPainter(this.scene, this.clock) : super(repaint: clock);

  final Scene scene;
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final maxLen = math.min(size.width, size.height) * _maxLenFraction * reachScale(scene, now);

    Offset innerPoint(double t) {
      final anchor = edgeAnchor(t, size);
      final inward = edgeInward(t, size);
      final fraction = fieldLengthAt(t, now, scene);
      final growth = _entranceGrowthAt(now, scene.introStart, t);
      final taper = edgeTaper(t, size);
      final length = maxLen * fraction * growth * taper;
      return anchor + inward * length;
    }

    // Outer boundary: the screen's own rim, corner to corner, down to the
    // true bottom-left/bottom-right points — with a small fillet rounding
    // the two top corners instead of a hard right angle.
    final cornerR = math.min(_topCornerRadius, math.min(size.width, size.height) / 2);
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, cornerR)
      ..quadraticBezierTo(0, 0, cornerR, 0)
      ..lineTo(size.width - cornerR, 0)
      ..quadraticBezierTo(size.width, 0, size.width, cornerR)
      ..lineTo(size.width, size.height);

    // Inner boundary: the field-driven curve, traced back from t=1 to t=0
    // and smoothed with the same quadratic-bezier-through-midpoints
    // technique `strokeMusicalLine` uses, so it reads as a flowing curve
    // rather than a faceted polyline. Near each end, `edgeTaper` has
    // already pulled these points in to meet the outer boundary almost
    // exactly, so closing the path here naturally pinches to a point at
    // the bottom corners instead of needing a separate end cap.
    final inner = <Offset>[
      for (var i = _rimSamples; i >= 0; i--) innerPoint(i / _rimSamples),
    ];
    path.lineTo(inner.first.dx, inner.first.dy);
    for (var i = 1; i < inner.length; i++) {
      final mid = Offset.lerp(inner[i - 1], inner[i], 0.5)!;
      path.quadraticBezierTo(inner[i - 1].dx, inner[i - 1].dy, mid.dx, mid.dy);
    }
    path.lineTo(inner.last.dx, inner.last.dy);
    path.close();

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        [
          FluidColors.lavender.withValues(alpha: _fillAlpha),
          FluidColors.deepPurple.withValues(alpha: _fillAlpha),
        ],
      )
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);

    // A small droplet, flicked inward from the rim whenever a loud moment
    // fires — see `activeDroplet`.
    final droplet = activeDroplet(now, scene, size);
    if (droplet != null) {
      final fade = 1 - Curves.easeIn.transform(droplet.progress);
      final radius = 5.0 * fade;
      if (radius > 0.3) {
        canvas.drawCircle(
          droplet.position,
          radius,
          Paint()..color = FluidColors.highlight.withValues(alpha: 0.85 * fade),
        );
      }
    }

    // Name tags for whichever notes are currently pulsing — see
    // `activeNoteBubbles`/`_paintNoteBubble`.
    for (final bubble in activeNoteBubbles(scene)) {
      final t = bubble.pitchClass / _spikeCount;
      final anchor = innerPoint(t) + edgeInward(t, size) * 18;
      _paintNoteBubble(canvas, anchor, bubble.note.pitch, bubble.envelope);
    }
  }

  @override
  bool shouldRepaint(FluidFieldPainter oldDelegate) => oldDelegate.scene != scene;
}
