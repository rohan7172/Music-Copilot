import 'package:flutter/material.dart';

import '../../models/harmony.dart';
import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/contour/contour_panel.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// What was heard, and chords that would go with it: the key and beat
/// grid up top, the companion with one insight, three progression cards
/// (Safe, Colourful, Bold) to swipe between, the tune as a contour with the
/// chosen chords above it, and the transport. Playing loops the chosen
/// progression under the take. Every chord opens its own "why".
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final suggestions = controller.suggestions;
    if (controller.confidentNotes.isEmpty ||
        suggestions == null ||
        suggestions.progressions.isEmpty) {
      return _NothingFound(controller: controller);
    }

    final key = suggestions.key;
    final grid = suggestions.grid;
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
              if (key != null)
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
              if (grid != null) ...[
                const SizedBox(width: Space.sm),
                InfoChip(
                  icon: grid.guessed
                      ? Icons.tune_rounded
                      : Icons.timer_outlined,
                  semanticLabel:
                      '${grid.bpm.round()} beats per minute. Adjust the beat grid',
                  onTap: () => _showGridSheet(context),
                  children: [
                    TextSpan(
                      text: '${grid.bpm.round()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: TextStyles.tabular,
                      ),
                    ),
                    const TextSpan(text: ' bpm'),
                  ],
                ),
              ],
            ],
          ),
          if (controller.songStage != null) ...[
            const SizedBox(height: Space.sm),
            _SongProgress(
              stage: controller.songStage!,
              progress: controller.songProgress,
            ),
          ] else if (controller.routeNote != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              controller.routeNote!,
              style: TextStyles.bodySm.copyWith(color: Palette.outline),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.sm),
          Center(child: SessionMascot(controller: controller, width: 96)),
          if (suggestions.insight != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              suggestions.insight!,
              style: TextStyles.labelMd.copyWith(height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.md),
          _ProgressionCards(
            controller: controller,
            onChordTap: (i) => _showChord(context, i),
          ),
          const SizedBox(height: Space.md),
          ContourPanel(
            controller: controller,
            onChordTap: (i) => _showChord(context, i),
          ),
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
                semanticLabel: controller.isPlaying
                    ? 'Pause'
                    : 'Play the take with these chords',
                onTap: controller.playbackReady ? controller.togglePlay : null,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: PillButton(
                  label: controller.withBacking ? 'chords on' : 'chords off',
                  icon: controller.withBacking
                      ? Icons.piano_rounded
                      : Icons.piano_off_rounded,
                  tone: controller.withBacking ? PillTone.soft : PillTone.quiet,
                  height: 48,
                  expand: true,
                  textStyle: TextStyles.labelMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  onTap: controller.toggleBacking,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showChord(BuildContext context, int index) {
    controller.playChord(index);
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
      builder: (context) => _ChordSheet(controller: controller, index: index),
    );
  }

  void _showGridSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
      builder: (context) => _GridSheet(controller: controller),
    );
  }
}

/// Safe / Colourful / Bold, swiped between. The card in view is the one
/// playing under the take and drawn above the contour.
class _ProgressionCards extends StatefulWidget {
  const _ProgressionCards({required this.controller, required this.onChordTap});

  final SessionController controller;
  final void Function(int index) onChordTap;

  @override
  State<_ProgressionCards> createState() => _ProgressionCardsState();
}

class _ProgressionCardsState extends State<_ProgressionCards> {
  late final PageController _pages = PageController(
    viewportFraction: 0.9,
    initialPage: widget.controller.selectedProgression,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final progressions = controller.suggestions!.progressions;
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _pages,
            itemCount: progressions.length,
            onPageChanged: controller.selectProgression,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: _ProgressionCard(
                progression: progressions[i],
                selected: i == controller.selectedProgression,
                activeChord: i == controller.selectedProgression
                    ? controller.activeChord
                    : null,
                onChordTap: (c) {
                  if (i != controller.selectedProgression) {
                    controller.selectProgression(i);
                  }
                  widget.onChordTap(c);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < progressions.length; i++)
              AnimatedContainer(
                duration: Motion.quick,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == controller.selectedProgression ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == controller.selectedProgression
                      ? Palette.primary
                      : Palette.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProgressionCard extends StatelessWidget {
  const _ProgressionCard({
    required this.progression,
    required this.selected,
    required this.activeChord,
    required this.onChordTap,
  });

  final Progression progression;
  final bool selected;
  final int? activeChord;
  final void Function(int index) onChordTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.settle,
      curve: Motion.curve,
      padding: const EdgeInsets.fromLTRB(Space.md, 14, Space.md, 12),
      decoration: BoxDecoration(
        color: selected ? Palette.container : Palette.creamAlt,
        borderRadius: BorderRadius.circular(Shape.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(progression.title, style: TextStyles.labelLg),
              if (progression.source == 'llm' ||
                  progression.source == 'recognised') ...[
                const SizedBox(width: Space.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: const ShapeDecoration(
                    color: Palette.primaryFixed,
                    shape: StadiumBorder(),
                  ),
                  child: Text(
                    progression.source == 'llm'
                        ? 'AI idea · checked'
                        : 'from the recording',
                    style: TextStyles.labelSm.copyWith(
                      fontSize: 9,
                      letterSpacing: 0.2,
                      color: Palette.onPrimaryFixed,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  progression.character,
                  style: TextStyles.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: progression.chords.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => _ChordPill(
                chord: progression.chords[i],
                active: i == activeChord,
                onTap: () => onChordTap(i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChordPill extends StatelessWidget {
  const _ChordPill({
    required this.chord,
    required this.active,
    required this.onTap,
  });

  final ProgressionChord chord;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Palette.onPrimary : Palette.ink;
    final bg = active
        ? Palette.primary
        : switch (chord.fit) {
            ChordFit.fits => Palette.canvas,
            ChordFit.colour => Palette.noteSoft.withValues(alpha: 0.32),
            ChordFit.clash => Palette.error.withValues(alpha: 0.12),
          };
    return Pressable(
      onTap: onTap,
      semanticLabel:
          'Bar ${chord.bar + 1}: ${chord.uncertain ? 'maybe ' : ''}${chord.symbol}, ${chord.roman}. Tap for why',
      // A chord the recognition wasn't sure of looks unsure: faded, "maybe".
      child: Opacity(
        opacity: chord.uncertain && !active ? 0.55 : 1,
        child: AnimatedContainer(
          duration: Motion.quick,
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(chord.symbol, style: TextStyles.labelLg.copyWith(color: fg)),
              Text(
                chord.uncertain ? 'maybe' : chord.roman,
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
      ),
    );
  }
}

/// One chord's "why": what it is, how it sits with the tune, and the
/// reasons the engine (or the checked AI idea) gave.
class _ChordSheet extends StatelessWidget {
  const _ChordSheet({required this.controller, required this.index});

  final SessionController controller;
  final int index;

  static const _functionWords = {
    'tonic': 'home: where the music feels at rest',
    'predominant': 'moving away from home',
    'dominant': 'pulling back toward home',
  };
  static const _kindWords = {
    'diatonic': 'in the key',
    'seventh': 'in the key, with a seventh for colour',
    'sus': 'suspended: open, unresolved',
    'secondary': 'a secondary dominant: it leans into the next chord',
    'borrowed': 'borrowed from the parallel key',
    'chromatic': 'outside the key: a bold colour',
  };

  @override
  Widget build(BuildContext context) {
    final chord = controller.scene.chords[index];
    final (fitLabel, fitColor) = switch (chord.fit) {
      ChordFit.fits => ('fits the tune', Palette.primary),
      ChordFit.colour => ('adds colour', Palette.noteActive),
      ChordFit.clash => ('rubs against the tune', Palette.error),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(chord.symbol, style: TextStyles.headlineLg),
              const SizedBox(width: Space.sm),
              Text(
                chord.roman,
                style: TextStyles.headlineMd.copyWith(color: Palette.outline),
              ),
              const Spacer(),
              Text(
                'bar ${chord.bar + 1}',
                style: TextStyles.labelMd.copyWith(color: Palette.outline),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${_functionWords[chord.function] ?? chord.function} · ${_kindWords[chord.kind] ?? chord.kind}',
            style: TextStyles.bodySm,
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: fitColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                fitLabel,
                style: TextStyles.labelLg.copyWith(color: fitColor),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final reason in chord.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(reason, style: TextStyles.bodyLg),
            ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'hear it again',
            icon: Icons.play_arrow_rounded,
            tone: PillTone.soft,
            onTap: () => controller.playChord(index),
          ),
        ],
      ),
    );
  }
}

/// Fixing the beat grid when the guess was off: where beat 1 is, double or
/// half time, and how often the chords change.
class _GridSheet extends StatelessWidget {
  const _GridSheet({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final grid = controller.grid;
        if (grid == null) return const SizedBox.shrink();
        final busy = controller.regridding;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Beat grid', style: TextStyles.headlineMd),
              const SizedBox(height: Space.xs),
              Text(
                grid.guessed
                    ? 'Guessed from your singing. If the chords change in odd places, nudge it.'
                    : 'Set by the click you recorded with.',
                style: TextStyles.bodySm,
              ),
              const SizedBox(height: Space.lg),
              _GridRow(
                label: 'Beat 1',
                value: 'move the bar line',
                children: [
                  RoundAction(
                    icon: Icons.chevron_left_rounded,
                    size: 44,
                    semanticLabel: 'Move beat 1 one beat earlier',
                    onTap: busy ? null : () => controller.shiftDownbeat(-1),
                  ),
                  const SizedBox(width: Space.sm),
                  RoundAction(
                    icon: Icons.chevron_right_rounded,
                    size: 44,
                    semanticLabel: 'Move beat 1 one beat later',
                    onTap: busy ? null : () => controller.shiftDownbeat(1),
                  ),
                ],
              ),
              _GridRow(
                label: 'Tempo',
                value: '${grid.bpm.round()} bpm',
                children: [
                  PillButton(
                    label: '÷2',
                    onTap: busy ? null : () => controller.scaleTempo(0.5),
                  ),
                  const SizedBox(width: Space.sm),
                  PillButton(
                    label: '×2',
                    onTap: busy ? null : () => controller.scaleTempo(2),
                  ),
                ],
              ),
              _GridRow(
                label: 'Chords',
                value: controller.perBar == 1 ? 'one per bar' : 'two per bar',
                children: [
                  PillButton(
                    label: controller.perBar == 1
                        ? 'two per bar'
                        : 'one per bar',
                    onTap: busy ? null : controller.togglePerBar,
                  ),
                ],
              ),
              AnimatedOpacity(
                opacity: busy ? 1 : 0,
                duration: Motion.quick,
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Re-suggesting…',
                    style: TextStyles.bodySm.copyWith(color: Palette.outline),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.label,
    required this.value,
    required this.children,
  });

  final String label;
  final String value;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyles.labelLg),
                Text(value, style: TextStyles.bodySm),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// While the song's own chords are being found: what's happening, and how
/// far along, under the quick melody-based answer.
class _SongProgress extends StatelessWidget {
  const _SongProgress({required this.stage, required this.progress});

  final String stage;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Finding the song’s own chords: $stage',
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.md, 10, Space.md, 12),
        decoration: BoxDecoration(
          color: Palette.creamAlt,
          borderRadius: BorderRadius.circular(Shape.panel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Finding the song’s own chords · ${stage.toLowerCase()}',
              style: TextStyles.labelMd,
            ),
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress.clamp(0.04, 1.0)),
                duration: Motion.settle,
                curve: Motion.curve,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: Palette.tint,
                  color: Palette.primary,
                ),
              ),
            ),
          ],
        ),
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
            'I couldn’t pick out a clear tune. Try a steadier, sustained melody '
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
