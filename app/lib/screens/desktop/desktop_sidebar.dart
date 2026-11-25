import 'package:flutter/material.dart';

import '../../layout.dart';
import '../../session/scene.dart';
import '../../session/session_controller.dart';
import '../../services/local_backend/local_backend.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import '../views/idle_view.dart' show ClickToggle;

/// The desktop app's sidebar: the ways in (record, import, click), what
/// this take is, the state of the app's own analyzer, and the keyboard
/// shortcuts. On a phone the same controls live in the canvas instead.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.controller,
    required this.backend,
  });

  final SessionController controller;
  final LocalBackend backend;

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
    final recording = phase == Phase.recording;
    final analyzing = phase == Phase.analyzing;
    final settled = phase == Phase.settled && controller.error == null;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.container,
        border: Border(right: BorderSide(color: Palette.containerHighest)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md + 4,
          Space.lg,
          Space.md + 4,
          Space.md,
        ),
        // Scrolls only when the window is too short to fit it all.
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Palette.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            size: 18,
                            color: Palette.onPrimary,
                          ),
                        ),
                        const SizedBox(width: Space.sm + 2),
                        Text(
                          'Music Copilot',
                          style: TextStyles.labelLg.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Palette.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  const SectionLabel('new take'),
                  const SizedBox(height: Space.sm),
                  SidebarButton(
                    icon: recording ? Icons.stop_rounded : Icons.mic_rounded,
                    label: recording ? 'Stop and analyze' : 'Record',
                    shortcut: recording ? 'Space' : 'R',
                    primary: true,
                    onTap: analyzing
                        ? null
                        : recording
                        ? controller.stopAndAnalyze
                        : _record,
                  ),
                  const SizedBox(height: Space.sm),
                  SidebarButton(
                    icon: Icons.upload_file_rounded,
                    label: 'Import audio file…',
                    shortcut: commandShortcut('O'),
                    onTap: recording || analyzing
                        ? null
                        : controller.pickAndAnalyzeFile,
                  ),
                  const SizedBox(height: Space.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IgnorePointer(
                      ignoring: recording || analyzing,
                      child: AnimatedOpacity(
                        duration: Motion.quick,
                        opacity: recording || analyzing ? 0.45 : 1,
                        child: ClickToggle(controller: controller),
                      ),
                    ),
                  ),
                  if (settled) ...[
                    const SizedBox(height: Space.xl),
                    const SectionLabel('this take'),
                    const SizedBox(height: Space.sm),
                    _TakeFacts(controller: controller),
                    const SizedBox(height: Space.md),
                    SidebarButton(
                      icon: Icons.refresh_rounded,
                      label: 'Start over',
                      shortcut: 'Esc',
                      onTap: controller.newTake,
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: backend,
                    builder: (context, _) => backend.isManaged
                        ? _AnalyzerStatus(backend: backend)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: Space.md),
                  const _Shortcuts(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _record() {
    if (controller.error != null) controller.dismissError();
    controller.startRecording();
  }
}

/// A full-width sidebar action with its keyboard shortcut on the right.
class SidebarButton extends StatelessWidget {
  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Palette.onPrimary : Palette.ink;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: Motion.quick,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: primary ? Palette.primary : Palette.canvas,
          borderRadius: BorderRadius.circular(12),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: Palette.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyles.labelLg.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (shortcut != null)
              ExcludeSemantics(
                child: Text(
                  shortcut!,
                  style: TextStyles.labelMd.copyWith(
                    color: primary
                        ? Palette.onPrimary.withValues(alpha: 0.7)
                        : Palette.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TakeFacts extends StatelessWidget {
  const _TakeFacts({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final suggestions = controller.suggestions;
    final key = suggestions?.key;
    final grid = suggestions?.grid;
    final rows = <(String, String)>[
      if (key != null) ('Key', key.name),
      if (grid != null) ('Tempo', '${grid.bpm.round()} bpm'),
      ('Length', clockText(controller.scene.duration)),
      ('Notes', '${controller.confidentNotes.length}'),
      if (controller.progression != null)
        ('Chords', controller.progression!.title),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (name, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(name, style: TextStyles.bodySm),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyles.labelLg.copyWith(
                      fontFeatures: TextStyles.tabular,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The app's own analyzer (the Python backend it started): ready, still
/// setting up, or failed with a way to try again.
class _AnalyzerStatus extends StatelessWidget {
  const _AnalyzerStatus({required this.backend});

  final LocalBackend backend;

  @override
  Widget build(BuildContext context) {
    final (dot, title) = switch (backend.status) {
      BackendStatus.ready => (const Color(0xFF3FA372), 'Analyzer ready'),
      BackendStatus.failed => (Palette.error, 'Analyzer stopped'),
      BackendStatus.settingUp => (Palette.noteSoft, 'Setting up analyzer'),
      _ => (Palette.noteSoft, 'Starting analyzer'),
    };
    final detail = switch (backend.status) {
      BackendStatus.ready =>
        backend.adopted
            ? 'Using one that was already running'
            : 'Running locally',
      _ => backend.detail,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.canvas,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (backend.isBusy)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Palette.noteActive,
                    ),
                  )
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: Space.sm),
                Text(title, style: TextStyles.labelLg),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyles.bodySm.copyWith(fontSize: 12),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (backend.status == BackendStatus.failed) ...[
              const SizedBox(height: Space.sm),
              PillButton(
                label: 'Try again',
                icon: Icons.restart_alt_rounded,
                tone: PillTone.soft,
                height: 34,
                textStyle: TextStyles.labelMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                onTap: backend.restart,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Space', 'play / pause'),
      ('R', 'record'),
      (commandShortcut('O'), 'import a file'),
      ('L', 'loop'),
      ('Esc', 'cancel / start over'),
    ];
    final style = TextStyles.bodySm.copyWith(fontSize: 12);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, what) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      key,
                      style: style.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Palette.ink,
                      ),
                    ),
                  ),
                  Text(what, style: style.copyWith(color: Palette.outline)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
