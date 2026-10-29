import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../theme.dart';
import '../widgets/score_canvas.dart' show strokeMusicalLine;
import 'session_screen.dart';

// impeccable:direction-contract
// THESIS: the hero moment — one flowing line and a short musical pulse,
// nothing else, standing in for every generic app-loading screen.
// STORY: the line grows in from the left, three notes play, the line
// shrinks back out the same way it came — the screen is blank again before
// the cut to the home screen, so the hand-off is never a visible jump.
// FORM: brief-pinned — "one simple line representing music... a pulse that
// plays a certain note, two notes or three notes," now a distinct beat
// before the mascot, not merged into the home screen.

const _growDuration = 0.5;
const _holdDuration = 0.4;
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
    strokeMusicalLine(
      canvas,
      index: 1,
      x0: 0,
      x1: size.width,
      baselineY: size.height / 2,
      now: elapsed,
      amplitudeAt: (f) => 0,
      color: Palette.accent.withValues(alpha: 0.85),
      reveal: _reveal,
    );
  }

  @override
  bool shouldRepaint(_SplashLinePainter oldDelegate) => oldDelegate.elapsed != elapsed;
}
