import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'score_canvas.dart' show Phase, Scene, introDuration;

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

const _restingFloor = 0.12;

/// A pseudo-random spike index for a given peak timestamp — the classic
/// "hash a float through a scaled sine's fractional part" trick, picked so
/// the *same* [peakAt] always maps to the *same* spike for as long as that
/// peak's pulse is playing out (no popping to a different spot mid-pulse),
/// while consecutive peaks land on unrelated spikes.
int _pulseSpikeIndex(double peakAt) {
  final x = math.sin(peakAt * 78.233) * 43758.5453;
  final frac = x - x.floorToDouble();
  return (frac.abs() * _spikeCount).floor().clamp(0, _spikeCount - 1);
}

const _peakPulseDuration = 0.6;
const _peakPulseRiseFraction = 0.15;
const _peakPulseMagnitude = 0.95;

/// 0..[_peakPulseMagnitude]: a quick rise then a slower decay, the shape of
/// a real transient — not a symmetric blip.
double _peakPulseEnvelope(double now, double peakAt) {
  final t = ((now - peakAt) / _peakPulseDuration).clamp(0.0, 1.0);
  if (t >= 1.0) return 0.0;
  if (t < _peakPulseRiseFraction) {
    return _peakPulseMagnitude * Curves.easeOut.transform(t / _peakPulseRiseFraction);
  }
  final fall = (t - _peakPulseRiseFraction) / (1 - _peakPulseRiseFraction);
  return _peakPulseMagnitude * (1 - Curves.easeIn.transform(fall));
}

/// 0..1 how strongly spike [k] is reaching out while recording. Earlier
/// versions drove this from continuous noise alone, which read as "a
/// generic wave throughout the fluid" with no real connection to what was
/// being recorded. Instead: every spike sits at a calm [_restingFloor]
/// until [Scene.lastPeakAt] fires — the same "loudness just crossed a
/// threshold on a rising edge" signal that already drives the mascot's
/// listening bob — at which point *one* spike, chosen by [_pulseSpikeIndex],
/// gets a pronounced pulse that rises and decays. The pulse's existence and
/// timing are tied to the actual recording; only *where* it appears around
/// the rim is randomized, same as the prompt asked for.
double _recordingAmplitude(int k, double now, Scene scene) {
  final peakAt = scene.lastPeakAt;
  if (peakAt == null || _pulseSpikeIndex(peakAt) != k) return _restingFloor;
  return (_restingFloor + _peakPulseEnvelope(now, peakAt)).clamp(0.0, 1.0);
}

/// 0..1 how far inward the fluid reaches at rim position [t] — the same
/// `radius² / (distance² + 1)` falloff the reference prototype's fragment
/// shader sums per spike (see `Inpiration/ferroflow_music.html`'s field
/// function), just evaluated once per rim sample instead of once per pixel:
/// [_spikeCount] Gaussian bumps, one per pitch-class position, each with
/// its own amplitude (see [_recordingAmplitude]/[_idleAmplitude]), summed
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
    final amp = scene.phase == Phase.recording
        ? _recordingAmplitude(k, now, scene)
        : _idleAmplitude(k, now);
    sum += amp * math.exp(-(dt * dt) / (2 * _spikeWidthT * _spikeWidthT));
  }
  return (1 - math.exp(-sum * _saturationGain)).clamp(0.0, 1.0);
}

/// 1 while idle/recording, easing to 0 over the first 0.5s of analyzing (so
/// the fluid recedes rather than cutting), 0 once settled — Step 2 fills
/// the settled canvas with a note-wise fluid + chord bubbles instead.
double _phaseVisibility(Scene scene, double now) {
  switch (scene.phase) {
    case Phase.idle:
    case Phase.recording:
      return 1.0;
    case Phase.analyzing:
      final start = scene.analyzeStart;
      if (start == null) return 1.0;
      return 1.0 - ((now - start) / 0.5).clamp(0.0, 1.0);
    case Phase.settled:
      return 0.0;
  }
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
/// [Scene.analyzeStart]/[Scene.lastPeakAt]; no new `Scene` fields needed.
class FluidFieldPainter extends CustomPainter {
  FluidFieldPainter(this.scene, this.clock) : super(repaint: clock);

  final Scene scene;
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final visibility = _phaseVisibility(scene, now);
    if (visibility <= 0) return;

    final maxLen = math.min(size.width, size.height) * _maxLenFraction;

    Offset innerPoint(double t) {
      final anchor = edgeAnchor(t, size);
      final inward = edgeInward(t, size);
      final fraction = fieldLengthAt(t, now, scene);
      final growth = _entranceGrowthAt(now, scene.introStart, t);
      final taper = edgeTaper(t, size);
      final length = maxLen * fraction * growth * visibility * taper;
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
          FluidColors.lavender.withValues(alpha: _fillAlpha * visibility),
          FluidColors.deepPurple.withValues(alpha: _fillAlpha * visibility),
        ],
      )
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(FluidFieldPainter oldDelegate) => oldDelegate.scene != scene;
}
