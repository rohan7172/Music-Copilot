import 'package:flutter/material.dart';

import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// The start screen (Stitch "Idle"): the companion waiting in the middle of
/// the canvas, one invitation, and the two ways in — sing into the mic or
/// bring a file.
class IdleView extends StatelessWidget {
  const IdleView({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 560;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.margin),
          child: Column(
            children: [
              const Spacer(flex: 3),
              SessionMascot(controller: controller, width: compact ? 168 : 220),
              SizedBox(height: compact ? Space.md : Space.lg),
              Text(
                'Play something',
                style: TextStyles.headlineLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  'Sing or hum a tune and I’ll suggest chords that fit it, '
                  'and tell you why.',
                  style: TextStyles.bodyMd,
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: compact ? Space.lg : Space.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RoundAction(
                    icon: Icons.mic_rounded,
                    caption: 'Live mic',
                    semanticLabel: 'Record with the microphone',
                    tone: PillTone.primary,
                    onTap: controller.startRecording,
                  ),
                  const SizedBox(width: Space.xl),
                  RoundAction(
                    icon: Icons.upload_file_rounded,
                    caption: 'File import',
                    semanticLabel: 'Import an audio file',
                    onTap: controller.pickAndAnalyzeFile,
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              _ClickToggle(controller: controller),
              const Spacer(flex: 4),
            ],
          ),
        );
      },
    );
  }
}

/// An optional click while recording: with it, the beat grid is exact
/// instead of guessed. Tap to switch it on; then set its tempo.
class _ClickToggle extends StatelessWidget {
  const _ClickToggle({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.clickOn) {
      return InfoChip(
        icon: Icons.av_timer_rounded,
        semanticLabel: 'Click off. Tap to record with a click',
        onTap: controller.toggleClick,
        children: const [TextSpan(text: 'record with a click')],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundAction(
          icon: Icons.remove_rounded,
          size: 32,
          semanticLabel: 'Slower click',
          onTap: () => controller.changeClickTempo(-5),
        ),
        const SizedBox(width: Space.sm),
        InfoChip(
          icon: Icons.av_timer_rounded,
          semanticLabel:
              'Click on at ${controller.clickBpm.round()} bpm. Tap to turn off',
          onTap: controller.toggleClick,
          children: [
            const TextSpan(text: 'click '),
            TextSpan(
              text: '${controller.clickBpm.round()} bpm',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: TextStyles.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(width: Space.sm),
        RoundAction(
          icon: Icons.add_rounded,
          size: 32,
          semanticLabel: 'Faster click',
          onTap: () => controller.changeClickTempo(5),
        ),
      ],
    );
  }
}
