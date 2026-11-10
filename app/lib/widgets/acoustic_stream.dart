import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session/scene.dart';
import '../theme.dart';

/// The listening screen's "acoustic stream": the last few seconds of live
/// loudness as a row of rounded bars, newest on the right, ending in a
/// "now" dot. Each bar is one real 40 ms microphone sample (averaged in
/// small groups so the row reads calmly), not a decorative equalizer.
/// [fade] (1→0) flattens it while the take is being analyzed.
class AcousticStream extends StatelessWidget {
  const AcousticStream({
    super.key,
    required this.scene,
    required this.clock,
    this.fade = 1,
  });

  final Scene scene;
  final ValueNotifier<double> clock;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: CustomPaint(painter: _StreamPainter(scene, clock, fade)),
      ),
    );
  }
}

class _StreamPainter extends CustomPainter {
  _StreamPainter(this.scene, this.clock, this.fade) : super(repaint: clock);

  final Scene scene;
  final ValueNotifier<double> clock;
  final double fade;

  static const _barWidth = 4.0;
  static const _gap = 7.0;

  /// Samples averaged into each bar: 3 × 40 ms ≈ 8 bars a second.
  static const _group = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    const dotR = 6.0;
    final usable = size.width - dotR * 2 - 10;
    final count = math.max(1, (usable / (_barWidth + _gap)).floor());

    final live = scene.live;
    final bars = <double>[];
    for (var b = count - 1; b >= 0; b--) {
      final end = live.length - b * _group;
      final start = end - _group;
      if (end <= 0) {
        bars.add(0);
        continue;
      }
      var sum = 0.0;
      var k = 0;
      for (var i = math.max(0, start); i < end; i++) {
        sum += live[i];
        k++;
      }
      bars.add(k == 0 ? 0 : sum / k);
    }

    // A faint baseline the bars grow out of.
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = Palette.tint
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < bars.length; i++) {
      final age = 1 - i / math.max(1, bars.length - 1);
      final h = (4 + bars[i] * (size.height - 8)) * fade + 4 * (1 - fade);
      final x = i * (_barWidth + _gap) + _barWidth / 2;
      final color = Color.lerp(
        Palette.primary,
        Palette.fluid,
        age * 0.8,
      )!.withValues(alpha: 0.35 + 0.65 * (1 - age * 0.6));
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        Paint()
          ..color = color
          ..strokeWidth = _barWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    final dotX = size.width - dotR - 2;
    final level = liveVolume(live) * fade;
    canvas.drawCircle(
      Offset(dotX, midY),
      dotR + 6 + level * 6,
      Paint()..color = Palette.noteSoft.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      Offset(dotX, midY),
      dotR,
      Paint()..color = Palette.primary,
    );
  }

  @override
  bool shouldRepaint(_StreamPainter old) =>
      old.fade != fade || old.scene != scene;
}
