import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

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
    // The top row and the transport stay put with only the middle scrolling,
    // so scrolled content stops short of the liquid header and the play
    // button is always in reach.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.margin,
            Space.xs,
            Space.margin,
            0,
          ),
          child: Row(
            children: [
              // Icon-only so the key and tempo always fit beside it.
              RoundAction(
                icon: Icons.refresh_rounded,
                size: 32,
                semanticLabel: 'Start a new take',
                onTap: controller.newTake,
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
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                _Mixer(controller: controller),
                const SizedBox(height: Space.md),
                ContourPanel(
                  controller: controller,
                  onChordTap: (i) => _showChord(context, i),
                  label: switch (controller.lens) {
                    'melody' => controller.parts.first.name.toLowerCase(),
                    'bass' => 'bass line',
                    'harmony' => 'harmony',
                    'drums' => 'drums',
                    _ =>
                      controller.parts.isEmpty
                          ? 'vocal contour'
                          : controller.parts.first.name.toLowerCase(),
                  },
                  laneLabels: controller.lens == 'drums'
                      ? const {36: 'Kick', 38: 'Snare', 42: 'Hat'}
                      : null,
                  overlays: controller.lens == 'drums'
                      ? const []
                      : [for (final h in controller.audibleHarmonies) h.notes],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.margin,
            Space.sm,
            Space.margin,
            Space.xs,
          ),
          child: Row(
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
        ),
      ],
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

/// What you hear, as switches: each part of the recording and each
/// harmony line turns on and off on its own, so any combination plays
/// together (the low harmony with the bass and drums, say, or just the
/// high harmony with the melody). The chords' pad is the transport's
/// switch. Turning a part on shows its notes and role; turning a harmony
/// on draws it in the contour and says why it works.
class _Mixer extends StatelessWidget {
  const _Mixer({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final toggles = controller.mixToggles;
    final sources = toggles.where((t) => !t.isHarmony).toList();
    final lines = toggles.where((t) => t.isHarmony).toList();
    final part = controller.currentPart;
    final line = controller.harmony;
    final hint = TextStyles.labelSm.copyWith(
      color: Palette.outline,
      letterSpacing: 0.2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'what you hear',
          trailing: Text('tap to turn on or off', style: hint),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [for (final t in sources) _toggle(t, 36)],
        ),
        _card(
          part == null
              ? null
              : [
                  Text(
                    part.role,
                    style: TextStyles.bodyMd.copyWith(color: Palette.onSurface),
                  ),
                  if (part.detail != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(part.detail!, style: TextStyles.bodySm),
                  ],
                ],
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          SectionLabel(
            'harmonies',
            trailing: Text(
              'over the ${controller.progression?.title ?? ''} chords',
              style: hint,
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.sm),
                Expanded(child: _toggle(lines[i], 40, fill: true)),
              ],
            ],
          ),
          _card(
            line == null
                ? null
                : [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            line.character,
                            style: TextStyles.bodyMd.copyWith(
                              color: Palette.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          line.range,
                          style: TextStyles.labelMd.copyWith(
                            color: Palette.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(line.detail, style: TextStyles.bodySm),
                  ],
          ),
        ],
      ],
    );
  }

  Widget _toggle(MixToggle t, double height, {bool fill = false}) {
    final on = controller.isOn(t.id);
    return _Choice(
      label: t.label,
      selected: on,
      height: height,
      check: true,
      fill: fill,
      semanticLabel:
          '${t.label}: ${on ? 'on' : 'off'}. Tap to turn it ${on ? 'off' : 'on'}',
      onTap: () => controller.toggleTrack(t.id),
    );
  }

  /// An explanation that opens under its chips while there's one to show.
  Widget _card(List<Widget>? children) => AnimatedSize(
    duration: Motion.settle,
    curve: Motion.curve,
    alignment: Alignment.topCenter,
    child: children == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: Palette.container,
                borderRadius: BorderRadius.circular(Shape.panel),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
  );
}

/// A pill that's one of a set: filled when chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.semanticLabel,
    this.check = false,
    this.fill = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final String semanticLabel;

  /// A switch rather than one of a set: a tick shows when it's on.
  final bool check;

  /// Fills the width it's given (in a row of equal pills) rather than
  /// fitting its label.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: AnimatedContainer(
        duration: Motion.quick,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: fill ? Alignment.center : null,
        decoration: ShapeDecoration(
          color: selected ? Palette.primary : Palette.creamAlt,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (check && selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: Palette.onPrimary,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.labelMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? Palette.onPrimary : Palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
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

class _ProgressionCard extends StatefulWidget {
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
  State<_ProgressionCard> createState() => _ProgressionCardState();
}

class _ProgressionCardState extends State<_ProgressionCard> {
  final _chordScroll = ScrollController();
  final _pillKeys = <GlobalKey>[];

  @override
  void didUpdateWidget(_ProgressionCard old) {
    super.didUpdateWidget(old);
    final active = widget.activeChord;
    if (active != null && active != old.activeChord) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(active));
    }
  }

  /// Slides the chord row so the chord sounding now stays in view.
  void _reveal(int index) {
    if (!mounted || !_chordScroll.hasClients || index >= _pillKeys.length) {
      return;
    }
    final pill = _pillKeys[index].currentContext?.findRenderObject();
    if (pill == null) return;
    final position = _chordScroll.position;
    // Only this row's own viewport, not `ensureVisible`: that would also
    // scroll the page and swipe the cards as the music plays.
    final target = RenderAbstractViewport.of(pill)
        .getOffsetToReveal(pill, 0.5)
        .offset;
    _chordScroll.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: Motion.settle,
      curve: Motion.curve,
    );
  }

  @override
  void dispose() {
    _chordScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progression = widget.progression;
    while (_pillKeys.length < progression.chords.length) {
      _pillKeys.add(GlobalKey());
    }
    return AnimatedContainer(
      duration: Motion.settle,
      curve: Motion.curve,
      padding: const EdgeInsets.fromLTRB(Space.md, 14, Space.md, 12),
      decoration: BoxDecoration(
        color: widget.selected ? Palette.container : Palette.creamAlt,
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
            // Every pill is built, not just those in view, so the one
            // sounding can always be found and scrolled to.
            child: SingleChildScrollView(
              controller: _chordScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < progression.chords.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _ChordPill(
                      key: _pillKeys[i],
                      chord: progression.chords[i],
                      active: i == widget.activeChord,
                      onTap: () => widget.onChordTap(i),
                    ),
                  ],
                ],
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
    super.key,
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
