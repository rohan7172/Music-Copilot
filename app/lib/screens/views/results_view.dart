import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/harmony.dart';
import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/contour/contour_panel.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// What was heard (Stitch "Note Analysis"): the key and counts up top, the
/// companion reacting, the notes as a playable contour, the chords as
/// chips to audition, and the transport. The full plain-language
/// explanation is one tap away rather than always on screen.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final notes = controller.confidentNotes;
    if (notes.isEmpty) return _NothingFound(controller: controller);

    final scene = controller.scene;
    final key = scene.key;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.margin,
        Space.xs,
        Space.margin,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InfoChip(
                icon: Icons.refresh_rounded,
                semanticLabel: 'Start a new take',
                onTap: controller.newTake,
                children: const [TextSpan(text: 'new take')],
              ),
              const Spacer(),
              if (key != null) ...[
                Flexible(
                  flex: 0,
                  child: InfoChip(
                    dot: Palette.noteActive,
                    semanticLabel: 'Key: ${key.name}',
                    children: [
                      const TextSpan(
                        text: 'key: ',
                        style: TextStyle(color: Palette.onSurfaceVariant),
                      ),
                      TextSpan(
                        text: key.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
              ],
              InfoChip(
                icon: Icons.music_note_rounded,
                semanticLabel: '${notes.length} notes',
                children: [
                  TextSpan(
                    text: '${notes.length}',
                    style: const TextStyle(fontFeatures: TextStyles.tabular),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Center(child: SessionMascot(controller: controller, width: 120)),
          const SizedBox(height: Space.sm),
          ValueListenableBuilder<double>(
            valueListenable: controller.clock,
            builder: (context, _, _) => Text(
              _descriptor(),
              style: TextStyles.labelMd,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: Space.md),
          ContourPanel(controller: controller),
          if (scene.chords.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            SectionLabel(
              'chords',
              trailing: Text(
                'tap to audition',
                style: TextStyles.labelSm.copyWith(
                  color: Palette.outline,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            ValueListenableBuilder<double>(
              valueListenable: controller.clock,
              builder: (context, _, _) => _ChordRow(controller: controller),
            ),
          ],
          const SizedBox(height: Space.lg),
          Row(
            children: [
              RoundAction(
                icon: Icons.repeat_rounded,
                size: 48,
                semanticLabel: controller.loop ? 'Loop on' : 'Loop off',
                selected: controller.loop,
                onTap: controller.toggleLoop,
              ),
              const SizedBox(width: Space.md),
              RoundAction(
                icon: controller.isPlaying && controller.scene.playingAll
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 56,
                tone: PillTone.primary,
                semanticLabel: controller.isPlaying ? 'Pause' : 'Play the take',
                onTap: controller.playbackReady ? controller.togglePlay : null,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: PillButton(
                  label: 'why it works',
                  trailingIcon: Icons.arrow_forward_rounded,
                  tone: PillTone.soft,
                  height: 48,
                  expand: true,
                  textStyle: TextStyles.labelMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  onTap: controller.explanation == null
                      ? null
                      : () => _showExplanation(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The line under the mascot: what's sounding while playing, otherwise
  /// how sure the key is.
  String _descriptor() {
    final scene = controller.scene;
    final playhead = scene.playhead;
    if (scene.playingAll && playhead != null) {
      final chord = controller.activeChord;
      final sounding = [
        for (final n in controller.confidentNotes)
          if (playhead >= n.startTime && playhead < n.endTime) n.pitch,
      ];
      final parts = [
        if (chord != null) scene.chords[chord].name,
        ...sounding.take(3),
      ];
      return parts.isEmpty
          ? 'playing · ${clockText(playhead)}'
          : parts.join(' · ');
    }
    final key = scene.key;
    if (key == null) return 'no clear key in this take';
    if (key.confidence >= 0.75) return 'sounds like ${key.name}';
    if (key.confidence >= 0.45) return 'probably ${key.name}';
    return 'maybe ${key.name}, not sure';
  }

  void _showExplanation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
      builder: (context) => _ExplanationSheet(controller: controller),
    );
  }
}

/// The detected chords as audition chips, scrolling sideways when there
/// are more than fit. The one sounding (or last tapped) is filled.
class _ChordRow extends StatelessWidget {
  const _ChordRow({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final chords = controller.scene.chords;
    final active = controller.activeChord;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chords.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) => _ChordChip(
          chord: chords[i],
          active: i == active,
          onTap: () => controller.playChord(i),
        ),
      ),
    );
  }
}

class _ChordChip extends StatelessWidget {
  const _ChordChip({
    required this.chord,
    required this.active,
    required this.onTap,
  });

  final Chord chord;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Palette.onPrimary : Palette.ink;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Play ${chord.name}, the ${chord.roman} chord',
      child: AnimatedContainer(
        duration: Motion.quick,
        constraints: const BoxConstraints(minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: ShapeDecoration(
          color: active ? Palette.primary : Palette.creamAlt,
          shape: const StadiumBorder(),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(chord.name, style: TextStyles.labelLg.copyWith(color: fg)),
            Text(
              chord.roman,
              style: TextStyles.labelSm.copyWith(
                fontSize: 9,
                letterSpacing: 0.2,
                color: active
                    ? Palette.onPrimary.withValues(alpha: 0.8)
                    : Palette.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plain-language explanation, opened on demand: the summary (each
/// chord it mentions is tappable, same as its chip) and a line per chord.
class _ExplanationSheet extends StatelessWidget {
  const _ExplanationSheet({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final explanation = controller.explanation!;
    final chords = controller.scene.chords;
    final linkStyle = TextStyles.bodyLg.copyWith(
      color: Palette.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: Palette.noteSoft,
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        children: [
          Text('Why it sounds this way', style: TextStyles.headlineMd),
          const SizedBox(height: Space.md),
          Text.rich(
            TextSpan(
              style: TextStyles.bodyLg,
              children: [
                for (final segment in explanation.summary)
                  segment.chordIndex == null
                      ? TextSpan(text: segment.text)
                      : TextSpan(
                          text: segment.text,
                          style: linkStyle,
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                controller.playChord(segment.chordIndex!),
                        ),
              ],
            ),
          ),
          if (explanation.chords.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            const SectionLabel('chord by chord'),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < explanation.chords.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Pressable(
                  pressedScale: 0.98,
                  onTap: i < chords.length
                      ? () => controller.playChord(i)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: Palette.creamAlt,
                      borderRadius: BorderRadius.circular(Shape.panel),
                    ),
                    child: Row(
                      children: [
                        if (i < chords.length) ...[
                          SizedBox(
                            width: 52,
                            child: Text(
                              chords[i].name,
                              style: TextStyles.musicNote,
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                        ],
                        Expanded(
                          child: Text(
                            explanation.chords[i].text,
                            style: TextStyles.bodyMd,
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Palette.outline,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Results came back with nothing confident to show.
class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.margin),
      child: Column(
        children: [
          const Spacer(flex: 3),
          SessionMascot(controller: controller, width: 180),
          const SizedBox(height: Space.lg),
          Text(
            'No notes found',
            style: TextStyles.headlineLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.sm),
          Text(
            'I couldn’t pick out a clear pitch. Try a steadier, sustained tone '
            'closer to the mic.',
            style: TextStyles.bodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          PillButton(
            label: 'Try again',
            icon: Icons.mic_rounded,
            tone: PillTone.primary,
            height: 52,
            onTap: controller.startRecording,
          ),
          const SizedBox(height: Space.sm + Space.xs),
          PillButton(label: 'Back to start', onTap: controller.newTake),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}
