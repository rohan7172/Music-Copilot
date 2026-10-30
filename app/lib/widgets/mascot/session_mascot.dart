import 'package:flutter/material.dart';

import '../../session/scene.dart';
import '../../session/session_controller.dart';
import 'mascot.dart';

/// The mascot wired to a live session: its mood is recomputed from the
/// session's real state every frame (see [moodFor]), it reacts to taps, and
/// while listening it hears the same live loudness the fluid does.
class SessionMascot extends StatelessWidget {
  const SessionMascot({super.key, required this.controller, this.width = 160});

  final SessionController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    return ValueListenableBuilder<double>(
      valueListenable: controller.clock,
      builder: (context, now, _) {
        final mood = moodFor(
          phase: scene.phase,
          now: now,
          hasError: controller.error != null,
          lastInteractionAt: controller.lastInteractionAt,
          lastTapAt: controller.lastTapAt,
          settleStart: scene.settleStart,
          playing: controller.isPlaying,
          noteCount: controller.confidentNotes.length,
          keyConfidence: scene.key?.confidence,
          boldSelected: controller.progression?.kind == 'bold',
          cadenceAt: controller.lastCadenceAt,
        );
        return Mascot(
          mood: mood,
          clock: controller.clock,
          width: width,
          level: () => liveVolume(scene.live),
          onTap: controller.tapMascot,
        );
      },
    );
  }
}
