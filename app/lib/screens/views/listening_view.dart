import 'package:flutter/material.dart';

import '../../session/scene.dart';
import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/acoustic_stream.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// Recording and analyzing (Stitch "Live Listening"): the companion
/// listening (then thinking), the live acoustic stream, and one way out.
/// Analyzing reuses this layout so the hand-off from "listening" to
/// "finding the notes" is a change of state, not a change of screen.
class ListeningView extends StatelessWidget {
  const ListeningView({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    final analyzing = scene.phase == Phase.analyzing;
    final timeStyle = TextStyles.labelSm.copyWith(
      color: Palette.outline,
      fontFeatures: TextStyles.tabular,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.margin,
        Space.xs,
        Space.margin,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: controller.clock,
                  builder: (context, _, _) => InfoChip(
                    dot: analyzing ? Palette.outline : Palette.primary,
                    semanticLabel: analyzing
                        ? 'Analyzing'
                        : 'Listening, ${clockText(scene.liveDuration)}',
                    children: [
                      TextSpan(text: analyzing ? 'analyzing' : 'listening  '),
                      if (!analyzing)
                        TextSpan(
                          text: clockText(scene.liveDuration),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: TextStyles.tabular,
                            color: Palette.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: analyzing ? 0 : 1,
                  duration: Motion.quick,
                  child: RoundAction(
                    icon: Icons.close_rounded,
                    size: 44,
                    semanticLabel: 'Discard this take',
                    onTap: analyzing ? null : controller.cancelRecording,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
          Center(child: SessionMascot(controller: controller, width: 220)),
          const SizedBox(height: Space.md),
          AnimatedSwitcher(
            duration: Motion.settle,
            child: Text(
              analyzing ? 'Finding the notes' : 'I’m listening',
              key: ValueKey(analyzing),
              style: TextStyles.headlineMd,
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(flex: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('00:00', style: timeStyle),
                    Expanded(
                      child: Text(
                        'acoustic stream',
                        style: TextStyles.labelMd.copyWith(
                          color: Palette.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: controller.clock,
                      builder: (context, _, _) =>
                          Text(clockText(scene.liveDuration), style: timeStyle),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: analyzing ? 0 : 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, fade, _) => AcousticStream(
                    scene: scene,
                    clock: controller.clock,
                    fade: fade,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.settle,
            child: analyzing
                ? SizedBox(
                    key: const ValueKey('analyzing'),
                    height: 56,
                    child: Center(
                      child: Text(
                        'Detecting pitches, then chords and key…',
                        style: TextStyles.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : PillButton(
                    key: const ValueKey('stop'),
                    label: 'Stop & analyze',
                    icon: Icons.stop_rounded,
                    tone: PillTone.primary,
                    height: 56,
                    expand: true,
                    textStyle: TextStyles.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    onTap: controller.stopAndAnalyze,
                  ),
          ),
          const SizedBox(height: Space.md),
          ValueListenableBuilder<double>(
            valueListenable: controller.clock,
            builder: (context, _, _) {
              final pastMin =
                  scene.liveDuration >= SessionController.autoStopMinRecording;
              final hint = analyzing
                  ? ''
                  : pastMin
                  ? 'Go quiet for 3 seconds and I’ll stop on my own.'
                  : 'Hum, sing, or strum — anything with a tune.';
              return AnimatedSwitcher(
                duration: Motion.settle,
                child: Text(
                  hint,
                  key: ValueKey(hint),
                  style: TextStyles.bodySm,
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
