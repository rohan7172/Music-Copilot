import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/harmony.dart';
import '../../models/note.dart';
import '../../note_range.dart';
import '../../session/scene.dart';
import '../../session/session_controller.dart';
import '../../theme.dart';
import '../ui.dart';
import 'contour_layout.dart';

/// The results screen's "VOCAL CONTOUR" panel: every confident note as a
/// pill on its pitch lane, a dashed thread tracing the melody, a playhead,
/// and a scrubber. Tap a pill to hear that note; tap or drag anywhere else
/// on the roll or the scrubber to play from there.
class ContourPanel extends StatelessWidget {
  const ContourPanel({
    super.key,
    required this.controller,
    this.onChordTap,
    this.label = 'vocal contour',
  });

  final SessionController controller;

  /// The panel heading: which part's notes are shown.
  final String label;

  /// A chord pill in the ribbon was tapped (index into the chosen
  /// progression's chords).
  final void Function(int index)? onChordTap;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    final visible = [
      for (var i = 0; i < scene.notes.length; i++)
        if (scene.notes[i].confidence >= noteConfidenceThreshold) i,
    ];
    final notes = [for (final i in visible) scene.notes[i]];

    return Container(
      padding: const EdgeInsets.fromLTRB(Space.md, 14, Space.md, 10),
      decoration: BoxDecoration(
        color: Palette.creamAlt,
        borderRadius: BorderRadius.circular(Shape.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            label,
            trailing: ValueListenableBuilder<double>(
              valueListenable: controller.clock,
              builder: (context, _, _) =>
                  _SoundingNow(scene: scene, notes: notes),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = ContourLayout(
                  size: constraints.biggest,
                  notes: notes,
                  duration: scene.duration,
                );
                return Semantics(
                  label:
                      'Note roll with ${notes.length} notes. '
                      'Tap a note to hear it.',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final chord = layout.hitChord(d.localPosition, [
                        for (final c in scene.chords) (c.startTime, c.endTime),
                      ]);
                      if (chord != null) {
                        onChordTap?.call(chord);
                        return;
                      }
                      final hit = layout.hitNote(d.localPosition);
                      if (hit != null) {
                        controller.playNote(visible[hit]);
                      } else {
                        controller.seek(layout.timeForX(d.localPosition.dx));
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: Palette.canvas,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _ContourPainter(
                            layout: layout,
                            scene: scene,
                            visible: visible,
                            clock: controller.clock,
                            grid: controller.grid,
                            activeChord: () => controller.activeChord,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _Scrubber(controller: controller),
        ],
      ),
    );
  }
}

/// The trailing label on the panel heading: the note sounding right now.
class _SoundingNow extends StatelessWidget {
  const _SoundingNow({required this.scene, required this.notes});

  final Scene scene;
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final playhead = scene.playhead;
    String? label;
    if (playhead != null) {
      final sounding = notes.where(
        (n) => playhead >= n.startTime && playhead < n.endTime,
      );
      if (sounding.isNotEmpty) {
        final top = sounding.reduce(
          (a, b) => a.midiPitch >= b.midiPitch ? a : b,
        );
        label = top.pitch;
      }
    }
    return AnimatedOpacity(
      opacity: label == null ? 0 : 1,
      duration: Motion.quick,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label ?? '',
            style: TextStyles.labelSm.copyWith(color: Palette.noteActive),
          ),
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Palette.noteActive,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContourPainter extends CustomPainter {
  _ContourPainter({
    required this.layout,
    required this.scene,
    required this.visible,
    required this.clock,
    required this.grid,
    required this.activeChord,
  }) : super(repaint: clock);

  final BeatGrid? grid;
  final int? Function() activeChord;

  final ContourLayout layout;
  final Scene scene;

  /// Index into [Scene.notes] for each of [layout]'s notes.
  final List<int> visible;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    _paintGrid(canvas, size);
    _paintBars(canvas, size);
    _paintRibbon(canvas, now);

    // Notes land one after another when results first appear.
    final settle = scene.settleStart ?? -10;
    final n = layout.notes.length;
    final stagger = math.min(0.045, 1.0 / math.max(1, n));
    double arrival(int i) => Curves.easeOutBack.transform(
      ((now - settle - 0.15 - i * stagger) / 0.38).clamp(0.0, 1.0),
    );

    final threadReveal = ((now - settle - 0.2) / 0.9).clamp(0.0, 1.0);
    _paintThread(canvas, threadReveal);

    final playhead = scene.playhead;
    for (var i = 0; i < n; i++) {
      final a = arrival(i);
      if (a <= 0) continue;
      final note = layout.notes[i];
      final sounding =
          playhead != null &&
          playhead >= note.startTime &&
          playhead < note.endTime;
      final active =
          sounding || (!scene.playingAll && scene.selected == visible[i]);
      _paintPill(canvas, layout.pill(i), note, active, a);
    }

    if (playhead != null) _paintPlayhead(canvas, size, playhead);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = Palette.tint
      ..strokeWidth = 1;
    for (final midi in layout.gridPitches()) {
      final y = layout.yForMidi(midi).roundToDouble() + 0.5;
      canvas.drawLine(Offset(layout.left - 4, y), Offset(size.width, y), rule);
      final label = TextPainter(
        text: TextSpan(
          text: midiName(midi),
          style: TextStyles.labelSm.copyWith(
            fontSize: 9,
            letterSpacing: 0.2,
            color: Palette.outline,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(6, y - label.height / 2));
    }
  }

  /// A faint line at every bar, so each chord's span reads against the tune.
  void _paintBars(Canvas canvas, Size size) {
    final g = grid;
    if (g == null) return;
    final paint = Paint()
      ..color = Palette.outlineVariant.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final beat in g.beats) {
      if (!beat.downbeat) continue;
      final x = layout.xForTime(beat.time);
      if (x <= layout.left + 0.5 || x >= layout.right - 0.5) continue;
      final px = x.roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(px, ContourLayout.ribbonHeight),
        Offset(px, size.height),
        paint,
      );
    }
  }

  /// The chosen progression above the roll, a pill per bar: tinted by how
  /// it sits with the melody, filled while it sounds or when tapped.
  void _paintRibbon(Canvas canvas, double now) {
    final chords = scene.chords;
    if (chords.isEmpty) return;
    final settle = scene.settleStart ?? -10;
    final active = activeChord();
    for (var i = 0; i < chords.length; i++) {
      final c = chords[i];
      final a = Curves.easeOutCubic.transform(
        ((now - settle - 0.5 - i * 0.05) / 0.4).clamp(0.0, 1.0),
      );
      if (a <= 0) continue;
      final r = layout.chordRect(c.startTime, c.endTime);
      final on = i == active;
      final fill = on
          ? Palette.primary
          : switch (c.fit) {
              ChordFit.fits => Palette.containerHighest,
              ChordFit.colour => Palette.noteSoft.withValues(alpha: 0.4),
              ChordFit.clash => Palette.error.withValues(alpha: 0.14),
            };
      // A recognised chord the model wasn't sure of is drawn fainter.
      final sure = c.uncertain && !on ? 0.5 : 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)),
        Paint()..color = fill.withValues(alpha: fill.a * a * sure),
      );
      final label = TextPainter(
        text: TextSpan(
          text: c.symbol,
          style: TextStyles.labelSm.copyWith(
            fontSize: 9.5,
            letterSpacing: -0.2,
            color: (on ? Palette.onPrimary : Palette.ink).withValues(alpha: a),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (label.width + 3 <= r.width) {
        label.paint(
          canvas,
          Offset(r.center.dx - label.width / 2, r.center.dy - label.height / 2),
        );
      }
    }
  }

  void _paintThread(Canvas canvas, double reveal) {
    if (reveal <= 0) return;
    final paint = Paint()
      ..color = Palette.noteActive.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final limitX = layout.left + layout.width * reveal;
    for (final run in layout.thread()) {
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (var k = 1; k < run.length; k++) {
        final a = run[k - 1];
        final b = run[k];
        final midX = (a.dx + b.dx) / 2;
        path.cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
      }
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, limitX, layout.size.height));
      for (final metric in path.computeMetrics()) {
        // Dashed, as in the Stitch contour: 3 on, 4 off.
        for (var d = 0.0; d < metric.length; d += 7) {
          canvas.drawPath(
            metric.extractPath(d, math.min(d + 3, metric.length)),
            paint,
          );
        }
      }
      canvas.restore();
    }
  }

  void _paintPill(
    Canvas canvas,
    Rect rect,
    Note note,
    bool active,
    double arrival,
  ) {
    final label = TextPainter(
      text: TextSpan(
        text: note.pitch,
        style: TextStyles.labelSm.copyWith(
          fontSize: 10,
          letterSpacing: 0,
          color: active ? Palette.onPrimary : Palette.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // A sounding note too short to fit its own name grows just enough to
    // show it, so what you hear always has a name on screen.
    var r = rect;
    final needed = label.width + 10;
    if (active && r.width < needed) {
      r = Rect.fromLTWH(
        math.min(r.left, layout.right - needed),
        r.top,
        needed,
        r.height,
      );
    }

    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.scale(0.6 + 0.4 * arrival);
    canvas.translate(-r.center.dx, -r.center.dy);
    final opacity = arrival.clamp(0.0, 1.0);
    final shape = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    final color = active
        ? Palette.noteActive
        // Unlabelled pills need more presence than the Stitch tint alone.
        : Color.lerp(
            Palette.containerHighest,
            Palette.noteSoft,
            note.confidence >= 0.7 ? 0.4 : 0.2,
          )!;
    canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: opacity));
    if (r.width >= needed) {
      canvas.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      label.paint(
        canvas,
        Offset(
          r.left + (r.width - label.width) / 2,
          r.center.dy - label.height / 2,
        ),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintPlayhead(Canvas canvas, Size size, double playhead) {
    final x = layout.xForTime(playhead);
    final paint = Paint()
      ..color = Palette.primary
      ..strokeWidth = 2;
    const top = ContourLayout.ribbonHeight;
    canvas.drawLine(Offset(x, top), Offset(x, size.height), paint);
    canvas.drawCircle(
      Offset(x, top + 1),
      4.5,
      Paint()..color = Palette.primary,
    );

    final tag = TextPainter(
      text: TextSpan(
        text: playhead.toStringAsFixed(1),
        style: TextStyles.labelSm.copyWith(
          fontSize: 9,
          letterSpacing: 0.2,
          color: Palette.onPrimary,
          fontFeatures: TextStyles.tabular,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tag.width + 10;
    final left = (x - w / 2).clamp(0.0, size.width - w);
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, size.height - 17, w, 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(box, Paint()..color = Palette.primary);
    tag.paint(
      canvas,
      Offset(left + 5, size.height - 17 + (14 - tag.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_ContourPainter old) =>
      old.layout.size != layout.size ||
      old.scene != scene ||
      old.visible != visible;
}

/// 00:00 ——●—— 00:12, tap or drag to play from a point.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.controller});

  final SessionController controller;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// While dragging, where the thumb is (0..1); seeking happens on release.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final scene = widget.controller.scene;
    final duration = scene.duration;
    final timeStyle = TextStyles.labelSm.copyWith(
      color: Palette.outline,
      fontFeatures: TextStyles.tabular,
    );
    return Row(
      children: [
        Text('00:00', style: timeStyle),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth - 24;
              double fractionAt(double dx) => ((dx - 12) / w).clamp(0.0, 1.0);
              return Semantics(
                slider: true,
                label: 'Playback position',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => widget.controller.seek(
                    fractionAt(d.localPosition.dx) * duration,
                  ),
                  onHorizontalDragStart: (d) =>
                      setState(() => _drag = fractionAt(d.localPosition.dx)),
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _drag = fractionAt(d.localPosition.dx)),
                  onHorizontalDragEnd: (_) {
                    final f = _drag;
                    setState(() => _drag = null);
                    if (f != null) widget.controller.seek(f * duration);
                  },
                  child: SizedBox(
                    height: 32,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.controller.clock,
                      builder: (context, _, _) {
                        final f =
                            _drag ??
                            ((scene.playhead ?? 0) / math.max(duration, 0.001))
                                .clamp(0.0, 1.0);
                        return CustomPaint(painter: _ScrubPainter(f));
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Text(clockText(duration), style: timeStyle),
      ],
    );
  }
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0;
    final y = size.height / 2;
    final x0 = inset;
    final x1 = size.width - inset;
    final x = x0 + (x1 - x0) * fraction;
    final track = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), track..color = Palette.tint);
    if (fraction > 0) {
      canvas.drawLine(
        Offset(x0, y),
        Offset(x, y),
        track..color = Palette.fluid,
      );
    }
    canvas.drawCircle(Offset(x, y), 8, Paint()..color = Palette.canvas);
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = Palette.primary);
  }

  @override
  bool shouldRepaint(_ScrubPainter old) => old.fraction != fraction;
}
