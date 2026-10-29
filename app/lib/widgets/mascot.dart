import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'score_canvas.dart' show Phase, Scene;

// impeccable:direction-contract
// THESIS: a supporting character, not a dashboard centerpiece — its state
// always traces back to a real phase, never a generic idle loop.
// SIGNATURE INTERACTION: clock-timestamp-driven transitions (idle breathing
// + blink, listening whiskers that pulse with the live input level, an
// analyzing head-tilt, a settle "pop" when results arrive) — the same
// timestamp pattern ScorePainter already uses, no new animation machinery.
// FORM: brief-pinned, Inpiration/MASCOT_SUGGESTION1.png — a rounded "pill"
// head, two dot eyes, one curved mouth line.

/// Which expression the mascot shows for a given [Phase] — a pure mapping,
/// kept separate from the painting code so it's unit-testable without a
/// widget test.
enum MascotExpression { idle, listening, analyzing, revealing }

MascotExpression expressionForPhase(Phase phase) => switch (phase) {
  Phase.idle => MascotExpression.idle,
  Phase.recording => MascotExpression.listening,
  Phase.analyzing => MascotExpression.analyzing,
  Phase.settled => MascotExpression.revealing,
};

/// The app's recurring character. A supporting presence, not a dashboard
/// centerpiece: [size] is the caller's job to shrink once the user is
/// actively working (see `SessionScreen`), matching the reference's "never
/// half the screen once the user starts working."
class Mascot extends StatelessWidget {
  const Mascot({super.key, required this.scene, required this.clock, this.size = 96});

  final Scene scene;
  final ValueListenable<double> clock;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: MascotPainter(scene, clock)),
    );
  }
}

class MascotPainter extends CustomPainter {
  MascotPainter(this.scene, this.clock) : super(repaint: clock);

  final Scene scene;
  final ValueListenable<double> clock;

  static const _blinkCycle = 4.2;
  static const _blinkDuration = 0.14;
  static const _popDuration = 0.4;
  static const _mouthSettleDuration = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final center = Offset(size.width / 2, size.height / 2);
    final expression = expressionForPhase(scene.phase);

    final bodyW = size.width * 0.62;
    final bodyH = size.height * 0.86;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // A single overall scale per expression: a slow breath at rest, a brief
    // overshoot pop the moment results arrive. Never both at once.
    final scale = switch (expression) {
      MascotExpression.idle => 1.0 + 0.02 * math.sin(now * 1.1),
      MascotExpression.revealing => _popScale(now),
      _ => 1.0,
    };
    canvas.scale(scale);

    // A gentle head-tilt while thinking — the only rotation the mascot ever
    // does, so it reads as "this phase" rather than decoration.
    if (expression == MascotExpression.analyzing) {
      canvas.rotate(0.06 * math.sin(now * 1.6));
    }

    final bodyRect = Rect.fromCenter(center: Offset.zero, width: bodyW, height: bodyH);
    final bodyShape = RRect.fromRectAndRadius(bodyRect, Radius.circular(bodyW / 2));
    final bodyOpacity = expression == MascotExpression.analyzing ? 0.85 : 1.0;
    canvas.drawRRect(bodyShape, Paint()..color = Palette.accent.withValues(alpha: bodyOpacity));

    _paintEyes(canvas, bodyH, now, expression);
    _paintMouth(canvas, bodyW, bodyH, now, expression);
    canvas.restore();

    if (expression == MascotExpression.listening) {
      _paintWhiskers(canvas, center, bodyW, bodyH, now);
    }
  }

  /// `1.0` outside the reveal window; a brief overshoot-then-settle pop the
  /// moment [Scene.settleStart] fires, echoing the same pop used for a
  /// revealed chord.
  double _popScale(double now) {
    final start = scene.settleStart;
    if (start == null) return 1.0;
    final t = ((now - start) / _popDuration).clamp(0.0, 1.0);
    return 1.0 + 0.12 * (1 - Curves.easeOutBack.transform(t));
  }

  void _paintEyes(Canvas canvas, double bodyH, double now, MascotExpression expression) {
    final eyeY = -bodyH * 0.14;
    final eyeDx = bodyH * 0.165;
    final eyeRadius = bodyH * 0.05 * (expression == MascotExpression.listening ? 1.15 : 1.0);

    // A quick periodic blink at rest; a single, deliberate blink timed to
    // the settle pop instead, never both.
    double openness = 1.0;
    if (expression == MascotExpression.revealing) {
      final start = scene.settleStart;
      if (start != null) {
        final t = now - start;
        openness = (t < 0 || t > _blinkDuration * 2)
            ? 1.0
            : (1 - math.sin(math.pi * t / (_blinkDuration * 2))).clamp(0.08, 1.0);
      }
    } else {
      final phase = now % _blinkCycle;
      openness = phase > _blinkDuration
          ? 1.0
          : (1 - math.sin(math.pi * phase / _blinkDuration)).clamp(0.08, 1.0);
    }

    final eyeColor = Color.lerp(Palette.accent, Colors.black, 0.55)!;
    final paint = Paint()..color = eyeColor;
    for (final dx in [-eyeDx, eyeDx]) {
      canvas.save();
      canvas.translate(dx, eyeY);
      canvas.scale(1.0, openness);
      canvas.drawCircle(Offset.zero, eyeRadius, paint);
      canvas.restore();
    }
  }

  void _paintMouth(Canvas canvas, double bodyW, double bodyH, double now, MascotExpression expression) {
    final mouthY = bodyH * 0.12;
    final mouthW = bodyW * 0.42;

    // How deep the smile's curve dips — a resting curve, a slightly flatter
    // one while thinking, and a brief deeper smile right as results land.
    final depth = switch (expression) {
      MascotExpression.analyzing => bodyH * 0.03,
      MascotExpression.revealing => bodyH * _revealMouthDepthFactor(now),
      _ => bodyH * 0.06,
    };

    final mouthColor = Color.lerp(Palette.accent, Colors.black, 0.4)!;
    final path = Path()
      ..moveTo(-mouthW / 2, mouthY)
      ..quadraticBezierTo(0, mouthY + depth, mouthW / 2, mouthY);
    canvas.drawPath(
      path,
      Paint()
        ..color = mouthColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyH * 0.03
        ..strokeCap = StrokeCap.round,
    );
  }

  double _revealMouthDepthFactor(double now) {
    final start = scene.settleStart;
    if (start == null) return 0.06;
    final t = ((now - start) / _mouthSettleDuration).clamp(0.0, 1.0);
    return 0.06 + 0.05 * (1 - Curves.easeOut.transform(t));
  }

  /// Small curved ticks flanking the head, the mascot "noticing" sound —
  /// their length pulses with the actual live input level, never a
  /// decorative loop.
  void _paintWhiskers(Canvas canvas, Offset center, double bodyW, double bodyH, double now) {
    final level = scene.live.isEmpty ? 0.0 : scene.live.last.clamp(0.0, 1.0);
    final pulse = 0.5 + 0.5 * math.sin(now * 5);
    final length = bodyH * (0.1 + 0.14 * level * pulse);
    if (length <= 0) return;
    final paint = Paint()
      ..color = Color.lerp(Palette.accent, Colors.black, 0.25)!.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyH * 0.025
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final x = center.dx + side * (bodyW / 2 + bodyH * 0.06);
      final y = center.dy;
      final path = Path()
        ..moveTo(x, y - length / 2)
        ..quadraticBezierTo(x + side * length * 0.4, y, x, y + length / 2);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(MascotPainter oldDelegate) => oldDelegate.scene != scene;
}
