import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../audio/waveform.dart';
import '../models/note.dart';
import '../theme.dart';

enum Phase { idle, recording, analyzing, settled }

/// Everything the canvas draws. Owned and mutated by the session screen; the
/// painter only reads it. All animation is derived from timestamps on the
/// shared clock (seconds), so any phase can be replayed by resetting a time.
class Scene {
  Phase phase = Phase.idle;

  /// Live loudness (0..1) sampled while recording, evenly spaced over
  /// [liveDuration].
  final List<double> live = [];
  double liveDuration = 0;

  /// Precise envelope decoded from the finished recording.
  Waveform? waveform;
  double? morphStart;

  double? analyzeStart;
  List<double> hints = const [];

  List<Note> notes = const [];
  double? settleStart;
  int? selected;

  /// Current playback position (seconds) while audio is playing or paused.
  double? playhead;

  /// True while the whole recording is playing; notes light up as they sound.
  bool playingAll = false;
}

// Timings (seconds).
const _morphTime = 0.7;
const _flightTime = 0.9;
const _liveWindow = 6.0;

double settleStagger(int noteCount) =>
    math.min(0.11, 1.6 / math.max(1, noteCount));

/// Where things sit on screen. Shared by the painter and the screen's hit
/// testing.
class SceneLayout {
  SceneLayout(this.size, this.scene) {
    final notes = scene.notes;
    if (notes.isEmpty) {
      _lo = 60;
      _hi = 72;
    } else {
      var lo = notes.map((n) => n.midiPitch).reduce(math.min) - 1;
      var hi = notes.map((n) => n.midiPitch).reduce(math.max) + 1;
      // Keep small melodies from stretching across the whole lane.
      final pad = math.max(0, 12 - (hi - lo));
      lo -= pad ~/ 2;
      hi += pad - pad ~/ 2;
      _lo = lo;
      _hi = hi;
    }
  }

  final Size size;
  final Scene scene;
  late final int _lo, _hi;

  double get left => 28;
  double get right => size.width - 28;
  double get width => right - left;
  double get waveY => size.height * 0.70;
  double get waveAmp => math.min(size.height * 0.11, 72);
  double get laneTop => size.height * 0.14;
  double get laneBottom => size.height * 0.50;

  double get duration => scene.waveform?.duration ?? 1;

  double xForTime(double t) => left + (t / duration).clamp(0.0, 1.0) * width;

  double yForMidi(int midi) =>
      laneBottom - (midi - _lo) / (_hi - _lo) * (laneBottom - laneTop);

  /// Point on the waveform's upper edge where a note begins.
  Offset origin(Note n) => Offset(
        xForTime(n.startTime),
        waveY - (scene.waveform?.at(n.startTime) ?? 0) * waveAmp,
      );

  /// Resting place of a note's head in the pitch lane.
  Offset target(Note n) => Offset(xForTime(n.startTime), yForMidi(n.midiPitch));
}

class ScorePainter extends CustomPainter {
  ScorePainter(this.scene, this.clock) : super(repaint: clock);

  final Scene scene;
  final ValueListenable<double> clock;

  static const _ink = Palette.ink;
  static const _accent = Palette.accent;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final layout = SceneLayout(size, scene);

    switch (scene.phase) {
      case Phase.idle:
        _paintIdleLine(canvas, layout);
      case Phase.recording:
        _paintLive(canvas, layout, 1);
      case Phase.analyzing:
      case Phase.settled:
        _paintRecorded(canvas, layout, now);
    }
  }

  // --- Idle -----------------------------------------------------------------

  /// The empty slate: a barely-there pen line the waveform will grow from.
  void _paintIdleLine(Canvas canvas, SceneLayout l) {
    final paint = Paint()
      ..color = _ink.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(l.left, l.waveY), Offset(l.right, l.waveY), paint);
  }

  // --- Recording ------------------------------------------------------------

  double _liveSpan(SceneLayout l) =>
      l.width * math.min(1, scene.liveDuration / _liveWindow);

  void _paintLive(Canvas canvas, SceneLayout l, double opacity, {double? spanOverride}) {
    final span = spanOverride ?? _liveSpan(l);
    // The unfilled remainder of the line, still waiting for sound.
    canvas.drawLine(
      Offset(l.left + span, l.waveY),
      Offset(l.right, l.waveY),
      Paint()
        ..color = _ink.withValues(alpha: 0.08 * opacity)
        ..strokeWidth = 1,
    );
    if (scene.live.length < 2) return;
    final path = _envelopePath(scene.live, 0, 1, l.left, l.left + span, l.waveY, l.waveAmp);
    canvas.drawPath(path, Paint()..color = _ink.withValues(alpha: 0.10 * opacity));
    canvas.drawPath(path, _strokePaint(_ink.withValues(alpha: 0.55 * opacity)));
    if (scene.phase == Phase.recording) {
      // The pen tip.
      final tip = Offset(l.left + span, l.waveY);
      canvas.drawCircle(tip, 3, Paint()..color = _accent.withValues(alpha: 0.8));
    }
  }

  // --- Analyzing & settled --------------------------------------------------

  void _paintRecorded(Canvas canvas, SceneLayout l, double now) {
    final waveform = scene.waveform;
    if (waveform == null) {
      _paintLive(canvas, l, 1);
      return;
    }

    final morph = Curves.easeInOutCubic
        .transform(((now - (scene.morphStart ?? now)) / _morphTime).clamp(0.0, 1.0));
    final span = ui.lerpDouble(_liveSpan(l), l.width, morph)!;
    if (morph < 1) _paintLive(canvas, l, 1 - morph, spanOverride: span);

    // While analyzing, the waveform breathes and a reading light sweeps it.
    final analyzing = scene.phase == Phase.analyzing;
    final amp = l.waveAmp * (analyzing ? 1 + 0.04 * math.sin(now * 2.2) : 1);
    final path = _envelopePath(waveform.envelope, 0, 1, l.left, l.left + span, l.waveY, amp);
    canvas.drawPath(path, Paint()..color = _ink.withValues(alpha: 0.10 * morph));
    final stroke = _strokePaint(_ink.withValues(alpha: 0.55 * morph));
    if (analyzing) {
      final sweep = ((now - (scene.analyzeStart ?? now)) % 1.8) / 1.8;
      final x = l.left + sweep * l.width;
      stroke.shader = ui.Gradient.linear(
        Offset(x - 90, 0),
        Offset(x + 90, 0),
        [
          _ink.withValues(alpha: 0.55 * morph),
          _accent.withValues(alpha: 0.95 * morph),
          _ink.withValues(alpha: 0.55 * morph),
        ],
        const [0, 0.5, 1],
      );
    }
    canvas.drawPath(path, stroke);

    final playhead = scene.playhead;
    if (playhead != null && scene.phase == Phase.settled) {
      final x = l.xForTime(playhead);
      canvas.drawLine(
        Offset(x, l.waveY - l.waveAmp - 8),
        Offset(x, l.waveY + l.waveAmp + 8),
        Paint()
          ..color = _accent.withValues(alpha: 0.7)
          ..strokeWidth = 1.2,
      );
    }

    _paintHints(canvas, l, now, morph);
    if (scene.phase == Phase.settled) _paintNotes(canvas, l, now);
  }

  /// Small dots lifting off the waveform's peaks: the app "listening closely".
  void _paintHints(Canvas canvas, SceneLayout l, double now, double morph) {
    if (scene.hints.isEmpty) return;
    var fade = morph;
    if (scene.phase == Phase.settled) {
      fade *= 1 - ((now - (scene.settleStart ?? now)) / 0.6).clamp(0.0, 1.0);
    }
    if (fade <= 0) return;
    for (var k = 0; k < scene.hints.length; k++) {
      final t = scene.hints[k];
      final pulse = (math.sin(now * 1.6 + k * 0.7) + 1) / 2;
      final base = l.waveY - scene.waveform!.at(t) * l.waveAmp;
      final y = base - 6 - 12 * pulse;
      canvas.drawCircle(
        Offset(l.xForTime(t), y),
        1.4 + 0.8 * pulse,
        Paint()..color = _accent.withValues(alpha: (0.2 + 0.5 * pulse) * fade),
      );
    }
  }

  void _paintNotes(Canvas canvas, SceneLayout l, double now) {
    final notes = scene.notes;
    final start = scene.settleStart ?? now;
    final stagger = settleStagger(notes.length);
    final selected = scene.selected;

    // Lane hairlines appear as each pitch first lands.
    final landed = <int, double>{};
    for (var i = 0; i < notes.length; i++) {
      final p = ((now - start - i * stagger) / _flightTime).clamp(0.0, 1.0);
      final arrive = ((p - 0.7) / 0.3).clamp(0.0, 1.0);
      final m = notes[i].midiPitch;
      landed[m] = math.max(landed[m] ?? 0, arrive);
    }
    final lanePaint = Paint()..strokeWidth = 1;
    landed.forEach((midi, a) {
      if (a <= 0) return;
      lanePaint.color = _ink.withValues(alpha: 0.05 * a);
      final y = l.yForMidi(midi);
      canvas.drawLine(Offset(l.left, y), Offset(l.right, y), lanePaint);
    });

    final labelRight = <int, double>{};
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final p = ((now - start - i * stagger) / _flightTime).clamp(0.0, 1.0);
      if (p <= 0) continue;

      final dim = selected == null || selected == i ? 1.0 : 0.3;
      final playhead = scene.playhead;
      final sounding = scene.playingAll &&
          playhead != null &&
          playhead >= note.startTime &&
          playhead <= note.endTime;
      final lit = selected == i || sounding;
      final conf = (0.4 + 0.6 * (note.confidence / 0.8).clamp(0.0, 1.0)) * dim;
      final from = l.origin(note);
      final to = l.target(note);
      final side = i.isEven ? 1.0 : -1.0;
      final control = Offset(from.dx + side * 28, (from.dy + to.dy) / 2);
      Offset along(double e) => _bezier(from, control, to, e);

      final e = Curves.easeOutCubic.transform(p);
      final arrive = Curves.easeOut.transform(((p - 0.7) / 0.3).clamp(0.0, 1.0));

      // The slice of waveform this note came from, now tinted.
      if (arrive > 0) {
        final segment = _envelopePath(
          scene.waveform!.envelope,
          note.startTime / l.duration,
          note.endTime / l.duration,
          l.xForTime(note.startTime),
          l.xForTime(note.endTime),
          l.waveY,
          l.waveAmp,
        );
        final tint = lit ? 0.3 : 0.05 * dim;
        canvas.drawPath(segment, Paint()..color = _accent.withValues(alpha: tint * arrive));

        // Thread tying the note back to where it was heard.
        canvas.drawLine(
          Offset(to.dx, from.dy),
          Offset(to.dx, to.dy + 6),
          Paint()
            ..color = _ink.withValues(alpha: (lit ? 0.25 : 0.06 * dim) * arrive)
            ..strokeWidth = 1,
        );

        // Duration stroke growing out of the head.
        final endX = to.dx + (l.xForTime(note.endTime) - to.dx) * arrive;
        canvas.drawLine(
          to,
          Offset(math.max(endX, to.dx + 0.1), to.dy),
          Paint()
            ..color = _accent.withValues(alpha: 0.28 * conf)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );

        // While its slice plays, the duration stroke fills in ink.
        if (lit && playhead != null && playhead > note.startTime) {
          final px = math.min(l.xForTime(playhead), l.xForTime(note.endTime));
          canvas.drawLine(
            to,
            Offset(px, to.dy),
            Paint()
              ..color = _accent.withValues(alpha: 0.85)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
        }
      }

      // Comet trail while in flight.
      if (p < 1) {
        for (var k = 1; k <= 6; k++) {
          final back = e - k * 0.035;
          if (back <= 0) break;
          canvas.drawCircle(
            along(back),
            2.4 * (1 - k / 8),
            Paint()..color = _accent.withValues(alpha: 0.35 * (1 - k / 7) * conf),
          );
        }
      }

      // Head: grows as it travels, with a small pop on landing.
      final pop = p > 0.8 ? math.sin(math.pi * (p - 0.8) / 0.2) : 0.0;
      final radius = (2.2 + 2.6 * e) * (1 + 0.35 * pop);
      final head = along(e);
      canvas.drawCircle(head, radius, Paint()..color = _accent.withValues(alpha: conf));
      if (lit) {
        canvas.drawCircle(
          head,
          radius + 5,
          _strokePaint(_accent.withValues(alpha: 0.6))..strokeWidth = 1.2,
        );
      }

      // Name, fading in once landed; skipped where it would collide.
      if (arrive > 0.3) {
        final painter = TextPainter(
          text: TextSpan(
            text: note.pitch,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: lit ? FontWeight.w600 : FontWeight.w400,
              color: _ink.withValues(alpha: 0.7 * ((arrive - 0.3) / 0.7) * dim),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = to.dx - painter.width / 2;
        final clear = x > (labelRight[note.midiPitch] ?? double.negativeInfinity) + 4;
        if (clear || lit) {
          painter.paint(canvas, Offset(x, to.dy - 20));
          labelRight[note.midiPitch] = x + painter.width;
        }
      }
    }
  }

  // --- Helpers --------------------------------------------------------------

  Paint _strokePaint(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..strokeJoin = StrokeJoin.round;

  static Offset _bezier(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }

  /// A smooth, mirrored outline of [envelope] between fractions [f0]..[f1],
  /// drawn from x0 to x1 around [cy]. Silence reads as a hairline, not a gap.
  static Path _envelopePath(
    List<double> envelope,
    double f0,
    double f1,
    double x0,
    double x1,
    double cy,
    double amp,
  ) {
    final count = math.max(2, math.min(envelope.length, ((x1 - x0) / 3).round()));
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var j = 0; j < count; j++) {
      final f = j / (count - 1);
      final v = sampleEnvelope(envelope, f0 + (f1 - f0) * f) * amp + 0.6;
      final x = x0 + (x1 - x0) * f;
      top.add(Offset(x, cy - v));
      bottom.add(Offset(x, cy + v));
    }
    final path = Path()..moveTo(top.first.dx, top.first.dy);
    _smoothThrough(path, top);
    final back = bottom.reversed.toList();
    path.lineTo(back.first.dx, back.first.dy);
    _smoothThrough(path, back);
    return path..close();
  }

  static void _smoothThrough(Path path, List<Offset> points) {
    for (var i = 1; i < points.length; i++) {
      final mid = Offset.lerp(points[i - 1], points[i], 0.5)!;
      path.quadraticBezierTo(points[i - 1].dx, points[i - 1].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
  }

  @override
  bool shouldRepaint(ScorePainter oldDelegate) => oldDelegate.scene != scene;
}
