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
                  'Sing, hum, or play anything and I’ll find the notes, '
                  'the chords and the key.',
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
              const Spacer(flex: 4),
            ],
          ),
        );
      },
    );
  }
}
