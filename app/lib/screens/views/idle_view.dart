import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/song.dart';

import '../../session/session_controller.dart';
import '../../theme.dart';
import '../../widgets/mascot/session_mascot.dart';
import '../../widgets/ui.dart';

/// The start screen (Stitch "Idle"): the companion waiting in the middle of
/// the canvas, one invitation, and the ways in: search for a song by name,
/// sing into the mic, let it listen to a song playing nearby, or bring a
/// file.
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
                  'Sing or hum a tune, or play a song near me, and I’ll '
                  'find chords and harmonies for it, and tell you why.',
                  style: TextStyles.bodyMd,
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: compact ? Space.md : Space.lg),
              _SongSearch(controller: controller),
              SizedBox(height: compact ? Space.md : Space.lg),
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
                  const SizedBox(width: Space.lg),
                  RoundAction(
                    icon: Icons.graphic_eq_rounded,
                    caption: 'Song playing',
                    semanticLabel:
                        'Listen to a song playing nearby and analyze it',
                    onTap: controller.listenToSong,
                  ),
                  const SizedBox(width: Space.lg),
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

/// Find a song by name. Results drop down under the field as you type; a
/// tap analyses that song's 30-second preview.
class _SongSearch extends StatefulWidget {
  const _SongSearch({required this.controller});

  final SessionController controller;

  @override
  State<_SongSearch> createState() => _SongSearchState();
}

class _SongSearchState extends State<_SongSearch> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  Timer? _debounce;
  int _request = 0;
  List<SongHit> _hits = const [];
  bool _searching = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_sync);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _open =>
      _focus.hasFocus &&
      _text.text.trim().isNotEmpty &&
      (_hits.isNotEmpty || _searching || _message != null);

  void _sync() {
    if (!mounted) return;
    setState(() {});
    _open ? _overlay.show() : _overlay.hide();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _request++;
      _hits = const [];
      _searching = false;
      _message = null;
      _sync();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final request = ++_request;
    _searching = true;
    _sync();
    List<SongHit> hits = const [];
    String? message;
    try {
      hits = await widget.controller.searchSongs(query);
      if (hits.isEmpty) message = 'No songs found for “$query”';
    } catch (_) {
      message = 'Can’t search right now. Is the analyzer running?';
    }
    if (request != _request) return; // a newer search has started
    _hits = hits;
    _message = message;
    _searching = false;
    _sync();
  }

  void _pick(SongHit hit) {
    _focus.unfocus();
    _overlay.hide();
    widget.controller.analyzeTrack(hit);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, Space.xs),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: math.min(
                  360,
                  MediaQuery.sizeOf(context).width - 2 * Space.margin,
                ),
                child: _results(_roomBelow(context)),
              ),
            ),
          ),
          child: TextField(
            key: _fieldKey,
            controller: _text,
            focusNode: _focus,
            onChanged: _changed,
            onSubmitted: (value) {
              if (_hits.isNotEmpty) _pick(_hits.first);
            },
            textInputAction: TextInputAction.search,
            style: TextStyles.bodyMd.copyWith(color: Palette.onSurface),
            decoration: InputDecoration(
              hintText: 'Search a song…',
              hintStyle: TextStyles.bodyMd.copyWith(color: Palette.outline),
              prefixIcon: const Icon(Icons.search_rounded, color: Palette.ink),
              suffixIcon: _text.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Palette.outline,
                      onPressed: () {
                        _text.clear();
                        _changed('');
                      },
                    ),
              filled: true,
              fillColor: Palette.container,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Shape.pill),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Shape.pill),
                borderSide: const BorderSide(
                  color: Palette.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How tall the results can be without running off the screen.
  double _roomBelow(BuildContext context) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context).height;
    if (box == null || !box.hasSize) return 320;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    return (screen - bottom - Space.lg).clamp(120.0, 320.0);
  }

  Widget _results(double maxHeight) {
    return Material(
      color: Palette.canvas,
      elevation: 6,
      shadowColor: Palette.ink.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(Shape.panel),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _hits.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(Space.md),
                child: _searching
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Text(
                        _message ?? '',
                        style: TextStyles.bodySm,
                        textAlign: TextAlign.center,
                      ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                shrinkWrap: true,
                children: [
                  for (final hit in _hits)
                    ListTile(
                      dense: true,
                      onTap: () => _pick(hit),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.square(
                          dimension: 40,
                          child: hit.artwork == null
                              ? const ColoredBox(
                                  color: Palette.container,
                                  child: Icon(Icons.music_note_rounded),
                                )
                              : Image.network(
                                  hit.artwork!,
                                  fit: BoxFit.cover,
                                  // Apple's image host sends no CORS
                                  // headers, so on the web the cover is
                                  // shown as a plain <img> element.
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.fallback,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: Palette.container,
                                    child: Icon(Icons.music_note_rounded),
                                  ),
                                ),
                        ),
                      ),
                      title: Text(
                        hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.labelLg,
                      ),
                      subtitle: Text(
                        hit.album == null
                            ? hit.artist
                            : '${hit.artist} · ${hit.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.bodySm,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
