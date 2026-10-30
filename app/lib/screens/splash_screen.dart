import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../theme.dart';
import '../widgets/app_frame.dart';
import '../widgets/mascot/mascot.dart';
import 'session_screen.dart';

// impeccable:direction-contract
// THESIS: the companion waking up to music is the app's first moment.
// STORY: the mascot fades in asleep; the three-note chime plays and it
// sings along (eyes shut, notes drifting off); on the last note it opens
// its eyes, and the session screen fades in around it.
// FORM: brief-pinned — the mascot sheet's Sleepy → Singing → Idle states,
// on the Stitch frame.

/// Seconds into the splash for each beat. The chime's three notes land at
/// 0, 0.27 and 0.54 s (see scripts/generate_splash_chime.py), so the
/// mascot sings through them and wakes just after the last one rings out.
const _singFrom = 0.18;
const _wakeAt = 0.95;
const _total = 1.9;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  );
  final ValueNotifier<double> _clock = ValueNotifier(0);
  final AudioPlayer _player = AudioPlayer();
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..addListener(() => _clock.value = _controller.value * _total)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      })
      ..forward();
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
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: const SessionScreen(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _clock.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: AppFrame(
        child: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: _clock,
            builder: (context, t, _) {
              final mood = t < _singFrom
                  ? MascotMood.sleepy
                  : t < _wakeAt
                  ? MascotMood.singing
                  : MascotMood.idle;
              final appear = Curves.easeOutCubic.transform((t / 0.35).clamp(0.0, 1.0));
              return Opacity(
                opacity: appear,
                child: Transform.scale(
                  scale: 0.92 + 0.08 * appear,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Mascot(mood: mood, clock: _clock, width: 220),
                      const SizedBox(height: Space.lg),
                      Text('Music Copilot', style: TextStyles.headlineMd),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
