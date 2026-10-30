import 'package:flutter/material.dart';

import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// When a take couldn't be captured or analyzed: says what happened, what
/// to do about it, and offers both ways back in.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.margin),
      child: Column(
        children: [
          const Spacer(flex: 3),
          SessionMascot(controller: controller, width: 180),
          const SizedBox(height: Space.lg),
          Text(
            error.title,
            style: TextStyles.headlineLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.sm),
          Text(
            error.message,
            style: TextStyles.bodyMd,
            textAlign: TextAlign.center,
          ),
          if (error.detail != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              error.detail!,
              style: TextStyles.bodySm.copyWith(color: Palette.outline),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: Space.xl),
          PillButton(
            label: 'Record again',
            icon: Icons.mic_rounded,
            tone: PillTone.primary,
            height: 52,
            onTap: () {
              controller.dismissError();
              controller.startRecording();
            },
          ),
          const SizedBox(height: Space.sm + Space.xs),
          PillButton(label: 'Back to start', onTap: controller.dismissError),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}
