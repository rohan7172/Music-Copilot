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

const _mainSpikeCount = 12;
const _ambientSpikeCount = 10;
const _totalSpikeCount = _mainSpikeCount + _ambientSpikeCount;

const _restBlurSigma = 14.0;
const _startBlurSigma = 30.0;
const _restContrast = 2.6;
const _startContrast = 1.0;

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

/// The direction a spike anchored at [t] grows inward — trivial per edge
/// (no trig needed, unlike a generic rectangle-ray cast) since the rim is
/// only ever one of three straight edges.
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
/// (`ribbonWobbleY`, the ambient drift) — continuous, so it needs no extra
/// smoothing to avoid reading as jittery, unlike a literal `Random()`.
double _noise(int i, double t) =>
    0.5 + 0.5 * math.sin(t * 1.7 + i * 2.31) * math.sin(t * 0.73 + i * 1.13);

/// 0..1 length fraction for spike [i] while recording — randomized, not
/// audio-driven: note-wise accuracy is explicitly out of scope for this
/// step (see docs/concepts.md), this is a depiction of "something is
/// flowing," not a detector.
double recordingLength(int i, double now) =>
    (0.45 + 0.4 * _noise(i, now * 0.5) + 0.15 * _noise(i + 31, now * 1.8))
        .clamp(0.0, 1.0);

/// 0..1 length fraction at rest (idle, or fading out while analyzing) — a
/// low, slow simmer rather than fully flat.
double idleLength(int i, double now) => 0.08 + 0.10 * _noise(i, now * 0.15);

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

/// 0 before the home screen's fluid has started growing in, 1 once fully
/// grown — [i] staggers each spike's own growth across a small span so the
/// rim rises unevenly, like liquid, rather than every spike snapping to
/// life in lockstep.
double _entranceGrowth(double now, double? introStart, int i, int n) {
  if (introStart == null) return 1.0;
  const staggerSpan = 0.5;
  final staggerOffset = (i / n) * staggerSpan;
  final local = ((now - introStart - staggerOffset) / (introDuration - staggerSpan))
      .clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(local);
}

/// 0..1 overall (non-staggered) entrance progress — drives the blur/contrast
/// ramp described in [FluidFieldPainter.paint], separate from each spike's
/// own staggered growth.
double _entranceProgress(double now, double? introStart) {
  if (introStart == null) return 1.0;
  return ((now - introStart) / introDuration).clamp(0.0, 1.0);
}

/// Sharpens a blurred, additively-summed alpha channel back into a clean
/// liquid edge. Note: the matrix's offset column is in 0–255 space, not the
/// 0–1 space the rest of this app's color math uses — the most common
/// mistake with this API.
ColorFilter _contrastSharpen(double contrast) {
  final bias = -0.5 * (contrast - 1) * 255;
  return ColorFilter.matrix([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, contrast, bias,
  ]);
}

/// A liquid/metaball-style field hugging the top and side edges of the
/// screen, leaving the bottom [fluidBottomReserve] clear for a future tab
/// bar. Approximates the metaball look of `Inpiration/ferroflow_music.html`
/// with a "goo" technique — blurred, additively-summed spike capsules,
/// sharpened back to a clean edge with a contrast filter — rather than a
/// ported fragment shader: this app has no existing shader infrastructure
/// and runs on Flutter web only, so stock `Canvas`/`Paint` primitives
/// (the same ones behind `BoxShadow.blurRadius`) are the lower-risk choice.
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

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final entranceT = Curves.easeOut.transform(
      _entranceProgress(now, scene.introStart),
    );
    final blurSigma = ui.lerpDouble(_startBlurSigma, _restBlurSigma, entranceT)!;
    final contrast = ui.lerpDouble(_startContrast, _restContrast, entranceT)!;

    // Two nested layers: the inner isolates `BlendMode.plus` so spikes sum
    // against each other and a transparent backdrop, not against the real
    // lines/mascot sitting behind this painter in z-order; the outer's
    // `colorFilter` sharpens the *merged* alpha only on restore().
    canvas.saveLayer(bounds, Paint()..colorFilter = _contrastSharpen(contrast));
    canvas.saveLayer(bounds, Paint());

    for (var i = 0; i < _mainSpikeCount; i++) {
      _paintSpike(
        canvas,
        size,
        now,
        seed: i,
        t: i / _mainSpikeCount,
        isMain: true,
        visibility: visibility,
        blurSigma: blurSigma,
        entranceGrowth: _entranceGrowth(now, scene.introStart, i, _totalSpikeCount),
      );
    }
    for (var j = 0; j < _ambientSpikeCount; j++) {
      final seed = _mainSpikeCount + j;
      _paintSpike(
        canvas,
        size,
        now,
        seed: seed,
        t: (j + 0.5) / _ambientSpikeCount,
        isMain: false,
        visibility: visibility,
        blurSigma: blurSigma,
        entranceGrowth: _entranceGrowth(now, scene.introStart, seed, _totalSpikeCount),
      );
    }

    canvas.restore();
    canvas.restore();
  }

  void _paintSpike(
    Canvas canvas,
    Size size,
    double now, {
    required int seed,
    required double t,
    required bool isMain,
    required double visibility,
    required double blurSigma,
    required double entranceGrowth,
  }) {
    final anchor = edgeAnchor(t, size, fluidBottomReserve);
    final inward = edgeInward(t, size, fluidBottomReserve);
    final lengthFraction = scene.phase == Phase.recording
        ? recordingLength(seed, now)
        : idleLength(seed, now);
    final maxLen = math.min(size.width, size.height) * (isMain ? 0.30 : 0.20);
    final length = maxLen * lengthFraction * entranceGrowth * visibility;
    if (length <= 0.5) return;
    final tip = anchor + inward * length;
    canvas.drawLine(
      anchor,
      tip,
      Paint()
        ..color = Color.lerp(
          FluidColors.lavender,
          FluidColors.deepPurple,
          lengthFraction,
        )!.withValues(alpha: 0.55)
        ..strokeWidth = isMain ? 15.0 : 9.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(FluidFieldPainter oldDelegate) => oldDelegate.scene != scene;
}
