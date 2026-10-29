import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../theme.dart';
import 'session_screen.dart';

// impeccable:direction-contract
// THESIS: the hero moment — one flowing line and a short musical pulse,
// nothing else, standing in for every generic app-loading screen.
// FIRST VIEWPORT: ivory ground, centered line, three soft ripples rising
// left-to-right in time with a three-note chime, then straight into the
// app. Tappable to skip.
// FORM: brief-pinned — "one simple line representing music... a pulse that
// plays a certain note, two notes or three notes."

/// The three notes in `assets/sounds/chime.wav` (see
/// scripts/generate_splash_chime.py) — kept in sync here so the line's
/// ripples land exactly on the notes the user hears.
const _noteOnsets = [0.0, 0.27, 0.54];
const _bumpDuration = 0.5;
const _totalDuration = 1.3;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
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
        transitionDuration: const Duration(milliseconds: 500),
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
        // Centered at a phone-like width on a wide (desktop) window, same
        // as the session screen, so the line doesn't stretch thin.
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
  _SplashLinePainter(this.now);

  final double now;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const samples = 140;
    final path = Path();
    final sigma = size.width * 0.1;
    final amplitude = size.height * 0.07;

    for (var i = 0; i < samples; i++) {
      final x = size.width * i / (samples - 1);
      var bump = 0.0;
      for (var j = 0; j < _noteOnsets.length; j++) {
        final anchorX = size.width * (j + 1) / (_noteOnsets.length + 1);
        final q = ((now - _noteOnsets[j]) / _bumpDuration).clamp(0.0, 1.0);
        if (q <= 0 || q >= 1) continue;
        final rise = math.sin(math.pi * q);
        final dist = x - anchorX;
        bump += rise * math.exp(-(dist * dist) / (2 * sigma * sigma));
      }
      final point = Offset(x, y - bump * amplitude);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final appear = (now / 0.3).clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = Palette.accent.withValues(alpha: 0.85 * appear)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SplashLinePainter oldDelegate) => oldDelegate.now != now;
}
