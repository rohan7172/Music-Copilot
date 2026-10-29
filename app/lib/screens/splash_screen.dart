import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../theme.dart';
import 'session_screen.dart';

// impeccable:direction-contract
// THESIS: the hero moment — one flowing line and a short musical pulse,
// nothing else, standing in for every generic app-loading screen.
// STORY: the line grows in from the left while three ripples rise along it
// in time with a three-note chime, then the line shrinks back out the same
// way it came — the screen is blank again before the cut to the home
// screen, so the hand-off is never a visible jump.
// FORM: brief-pinned — "one simple line representing music... a pulse that
// plays a certain note, two notes or three notes," now a distinct beat
// before the mascot, not merged into the home screen.

/// The three notes in `assets/sounds/chime.wav` (see
/// scripts/generate_splash_chime.py) — kept in sync here so the line's
/// ripples land exactly on the notes the user hears. The original, best
/// version of this animation; only the grow-in/shrink-out around it is new.
const _noteOnsets = [0.0, 0.27, 0.54];
const _bumpDuration = 0.5;

const _growDuration = 0.5;
// Long enough that all three ripples (the last starts at 0.54s and takes
// 0.5s to rise and fall) finish while the line is still fully grown, not
// swallowed mid-shrink.
const _holdDuration = 0.6;
const _shrinkDuration = 0.5;
const _totalDuration = _growDuration + _holdDuration + _shrinkDuration;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_totalDuration * 1000).round()),
  );
  final AudioPlayer _player = AudioPlayer();
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _advance();
    });
    unawaited(_playChime());
  }

  Future<void> _playChime() async {
    try {
      await _player.setAsset('assets/sounds/chime.wav');
      await _player.play();
    } catch (e) {
      // The splash still works without sound.
      debugPrint('Could not play splash chime: $e');
    }
  }

  void _advance() {
    if (_advanced || !mounted) return;
    _advanced = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, _) =>
            FadeTransition(opacity: animation, child: const SessionScreen()),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: Scaffold(
        backgroundColor: Palette.paper,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _SplashLinePainter(_controller.value * _totalDuration),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashLinePainter extends CustomPainter {
  _SplashLinePainter(this.elapsed);

  final double elapsed;

  /// 0..1: how much of the line is currently revealed — grows from 0 to 1,
  /// holds, then shrinks back to 0 the same way it came (the literal
  /// reverse of the grow-in), so the screen is blank again right before the
  /// cut to the home screen.
  double get _reveal {
    if (elapsed < _growDuration) {
      return Curves.easeOutCubic.transform(elapsed / _growDuration);
    }
    if (elapsed < _growDuration + _holdDuration) return 1.0;
    final shrinkT = (elapsed - _growDuration - _holdDuration) / _shrinkDuration;
    return 1.0 - Curves.easeInCubic.transform(shrinkT.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final reveal = _reveal;
    if (reveal <= 0) return;
    final y = size.height / 2;
    final sigma = size.width * 0.1;
    final amplitude = size.height * 0.07;
    final visibleX = size.width * reveal;

    const samples = 90;
    final points = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      if (x > visibleX + 0.01) break;
      var bump = 0.0;
      for (var j = 0; j < _noteOnsets.length; j++) {
        final anchorX = size.width * (j + 1) / (_noteOnsets.length + 1);
        final q = ((elapsed - _noteOnsets[j]) / _bumpDuration).clamp(0.0, 1.0);
        if (q <= 0 || q >= 1) continue;
        final rise = math.sin(math.pi * q);
        final dist = x - anchorX;
        bump += rise * math.exp(-(dist * dist) / (2 * sigma * sigma));
      }
      points.add(Offset(x, y - bump * amplitude));
    }
    if (points.length < 2) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final mid = Offset.lerp(points[i - 1], points[i], 0.5)!;
      path.quadraticBezierTo(points[i - 1].dx, points[i - 1].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = Palette.accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SplashLinePainter oldDelegate) => oldDelegate.elapsed != elapsed;
}
