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
const _rimSamples = 160;

/// How far inward the fluid can reach, as a fraction of the canvas's
/// shorter side.
const _maxLenFraction = 0.34;

const _restBlurSigma = 3.0;
const _startBlurSigma = 18.0;
const _fillAlpha = 0.88;

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

/// Two unrelated sine frequencies multiplied, [x] as the spatial phase (the
/// same role `f` plays in `ribbonWobbleY`) — the same "organic,
/// never-quite-looping" trick already used throughout this app. Continuous
/// in both [x] and [now], so neighboring rim samples stay close together
/// (no faceting) and nothing needs extra smoothing to avoid jitter.
double _ripple(double x, double now) =>
    0.5 + 0.5 * math.sin(now * 1.7 + x * 2.31) * math.sin(now * 0.73 + x * 1.13);

/// 0..1 how far inward the fluid reaches at rim position [t] while
/// recording — randomized, not audio-driven: note-wise accuracy is
/// explicitly out of scope for this step (see docs/concepts.md), this is a
/// depiction of "something is flowing," not a detector. Never drops below
/// 0.5, so the band always reads as a solid, clearly visible body rather
/// than pinching to nothing at some points around the rim.
double recordingLength(double t, double now) =>
    (0.5 + 0.35 * _ripple(t * 9.0, now * 1.0) + 0.15 * _ripple(t * 21.0, now * 2.4))
        .clamp(0.0, 1.0);

/// 0..1 how far inward the fluid reaches at rest (idle, or fading out while
/// analyzing) — a low, slow simmer, never below 0.22.
double idleLength(double t, double now) =>
    (0.22 + 0.10 * _ripple(t * 6.0, now * 0.3)).clamp(0.0, 1.0);

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

/// 0..1 overall (non-staggered) entrance progress — drives the blur ramp in
/// [FluidFieldPainter.paint], separate from each point's own staggered
/// growth.
double _entranceProgress(double now, double? introStart) {
  if (introStart == null) return 1.0;
  return ((now - introStart) / introDuration).clamp(0.0, 1.0);
}

/// A liquid/metaball-style field hugging the top and side edges of the
/// screen, leaving the bottom [fluidBottomReserve] clear for a future tab
/// bar. Approximates the look of `Inpiration/ferroflow_music.html` as one
/// continuous, solidly filled band — the screen's own edge as the outer
/// boundary, a smoothed, noise-driven wavy curve as the inner boundary —
/// rather than a blur-and-threshold blend of many small shapes: a first
/// version tried that (blurred, additively-summed spike capsules sharpened
/// back with a contrast filter), but small/short spikes lost so much mass
/// to the blur that they vanished entirely, and even the larger
/// recording-time spikes only read as faint, separate blobs rather than a
/// solid, clearly visible liquid body. A single filled path has no such
/// failure mode: its visibility never depends on tuning a blur radius
/// against a contrast threshold.
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
    final entranceT = Curves.easeOut.transform(
      _entranceProgress(now, scene.introStart),
    );
    final blurSigma = ui.lerpDouble(_startBlurSigma, _restBlurSigma, entranceT)!;

    Offset innerPoint(double t) {
      final anchor = edgeAnchor(t, size, fluidBottomReserve);
      final inward = edgeInward(t, size, fluidBottomReserve);
      final fraction = scene.phase == Phase.recording
          ? recordingLength(t, now)
          : idleLength(t, now);
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

    // Inner boundary: the wavy, noise-driven curve, traced back from t=1 to
    // t=0 and smoothed with the same quadratic-bezier-through-midpoints
    // technique `strokeMusicalLine` uses, so it reads as a flowing curve
    // rather than a faceted polyline.
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
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(FluidFieldPainter oldDelegate) => oldDelegate.scene != scene;
}
