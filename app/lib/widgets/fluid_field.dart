import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'score_canvas.dart' show Phase, Scene, introDuration;

/// How much of the screen's height, measured from the bottom, the fluid
/// never draws into — reserved for a future tab bar that doesn't exist yet.
/// Enforced by construction (see [edgeAnchor]), not by clipping after the
/// fact.
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
/// amplitude grows (recording).
const _spikeWidthT = 0.034;

/// A small always-present floor so the rim never shows a literal gap
/// between fingers, even at their quietest.
const _ambientFloor = 0.05;

/// How quickly the summed field saturates toward a full-strength fill —
/// see [fieldLengthAt].
const _saturationGain = 1.7;

const _fillAlpha = 0.94;

/// A point on the fluid's rim (left edge, top edge, right edge — never the
/// reserved bottom strip) for arc-length position [t] (0..1), given the
/// canvas [size]. Arc-length, not angle, parameterization: slicing by angle
/// bunches points at the corners once the bottom 90° is removed, arc-length
/// doesn't.
Offset edgeAnchor(double t, Size size, double bottomReserve) {
  final fluidBottom = size.height * (1 - bottomReserve);
  final leftLen = fluidBottom, topLen = size.width, rightLen = fluidBottom;
  final total = leftLen + topLen + rightLen;
  if (total <= 0) return Offset.zero;
  final d = t.clamp(0.0, 1.0) * total;
  if (d < leftLen) return Offset(0, fluidBottom - d);
  if (d < leftLen + topLen) return Offset(d - leftLen, 0);
  return Offset(size.width, d - leftLen - topLen);
}

/// The direction the fluid grows inward at rim position [t] — trivial per
/// edge (no trig needed, unlike a generic rectangle-ray cast) since the rim
/// is only ever one of three straight edges.
Offset edgeInward(double t, Size size, double bottomReserve) {
  final fluidBottom = size.height * (1 - bottomReserve);
  final leftLen = fluidBottom, topLen = size.width;
  final total = leftLen + topLen + fluidBottom;
  final d = t.clamp(0.0, 1.0) * total;
  if (d < leftLen) return const Offset(1, 0);
  if (d < leftLen + topLen) return const Offset(0, 1);
  return const Offset(-1, 0);
}

/// Two unrelated sine frequencies multiplied — the same "organic,
/// never-quite-looping" trick already used throughout this app
/// (`ribbonWobbleY`). [x] plays the role `f` plays there: a spatial seed so
/// each spike's amplitude drifts independently rather than in lockstep.
double _ripple(double x, double now) =>
    0.5 + 0.5 * math.sin(now * 1.7 + x * 2.31) * math.sin(now * 0.73 + x * 1.13);

/// 0..1 how strongly spike [k] (one of [_spikeCount], evenly spaced around
/// the rim) is reaching out right now. Randomized, not audio-driven — an
/// explicit, named scope cut: note-wise accuracy is out of scope for this
/// step (see docs/concepts.md), this is a depiction of "something is
/// flowing," not a detector.
double _spikeAmplitude(int k, double now, Phase phase) {
  if (phase == Phase.recording) {
    return (0.55 +
            0.35 * _ripple(k * 3.1, now * 0.8) +
            0.15 * _ripple(k * 7.7 + 11, now * 2.1))
        .clamp(0.0, 1.0);
  }
  return (0.14 + 0.10 * _ripple(k * 3.1, now * 0.25)).clamp(0.0, 1.0);
}

/// 0..1 how far inward the fluid reaches at rim position [t] — the same
/// `radius² / (distance² + 1)` falloff the reference prototype's fragment
/// shader sums per spike (see `Inpiration/ferroflow_music.html`'s field
/// function), just evaluated once per rim sample instead of once per pixel:
/// `[_spikeCount]` Gaussian bumps, one per pitch-class position, each with
/// its own independently-drifting amplitude, summed and passed through a
/// saturating curve so overlapping bumps blend into a taller, wider merged
/// lobe instead of just adding past 1 and clipping — the same "fingers
/// merge when close" character metaballs have, without needing an actual
/// 2D implicit-field threshold search.
double fieldLengthAt(double t, double now, Phase phase) {
  var sum = _ambientFloor;
  for (var k = 0; k < _spikeCount; k++) {
    final center = k / _spikeCount;
    var dt = (t - center).abs();
    dt = math.min(dt, 1 - dt); // the rim wraps around, so distance wraps too
    final amp = _spikeAmplitude(k, now, phase);
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
/// screen, leaving the bottom [fluidBottomReserve] clear for a future tab
/// bar — approximating the look of `Inpiration/ferroflow_music.html`
/// without porting its per-pixel fragment shader (this app has no shader
/// infrastructure and runs on Flutter web only, see docs/concepts.md).
///
/// Earlier versions of this painter tried to get the metaball look from
/// *rendering* tricks — first a blurred, additively-summed blend sharpened
/// with a contrast filter (small shapes lost too much mass to the blur and
/// vanished), then a single filled shape with a generic noise-driven wavy
/// edge softened by a blur (visible, but read as one hazy band, not
/// distinct organic fingers). This version instead gets the look from the
/// same *field math* the prototype uses — [fieldLengthAt] sums a
/// `radius²/(distance²+1)`-style falloff per pitch-class spike — and draws
/// the result as one crisp filled path with no blur at all: the organic,
/// merging-finger character comes from the field summation itself, not
/// from softening a shape after the fact.
///
/// Timestamp-driven off [clock], like every other painter in this app — no
/// `AnimationController`. Reads only [Scene.phase]/[Scene.introStart]/
/// [Scene.analyzeStart]; no new `Scene` fields needed.
class FluidFieldPainter extends CustomPainter {
  FluidFieldPainter(this.scene, this.clock) : super(repaint: clock);

  final Scene scene;
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final visibility = _phaseVisibility(scene, now);
    if (visibility <= 0) return;

    final fluidBottom = size.height * (1 - fluidBottomReserve);
    final maxLen = math.min(size.width, size.height) * _maxLenFraction;

    Offset innerPoint(double t) {
      final anchor = edgeAnchor(t, size, fluidBottomReserve);
      final inward = edgeInward(t, size, fluidBottomReserve);
      final fraction = fieldLengthAt(t, now, scene.phase);
      final growth = _entranceGrowthAt(now, scene.introStart, t);
      final length = maxLen * fraction * growth * visibility;
      return anchor + inward * length;
    }

    // Outer boundary: the screen's own rim, corner to corner — the fluid's
    // outer edge is always exactly the edge of the screen.
    final path = Path()
      ..moveTo(0, fluidBottom)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, fluidBottom);

    // Inner boundary: the field-driven curve, traced back from t=1 to t=0
    // and smoothed with the same quadratic-bezier-through-midpoints
    // technique `strokeMusicalLine` uses, so it reads as a flowing curve
    // rather than a faceted polyline — smoothing comes from this
    // interpolation and from the field's own Gaussian falloff, not from a
    // blur pass over the finished shape.
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
