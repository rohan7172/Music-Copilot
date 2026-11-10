import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'mascot_mood.dart';

export 'mascot_mood.dart';

/// The design box the mascot is drawn in. Every measurement below is in
/// these units, taken straight off the reference sheet's idle mascot
/// (`Inpiration/Mascot States and Emotions Sheet.png`, where the body is
/// 84 × 142 px) so the drawn character matches it proportion for
/// proportion; the painter just scales the box to the widget's size.
const _boxW = 220.0;
const _boxH = 200.0;

/// Where the body's top-center sits in the box — the room above and to the
/// sides is for accessories (sound arcs, ticks, notes, the "?").
const _origin = Offset(110, 28);

const _bodyW = 84.0;
const _bodyH = 142.0;
const _eyeX = 18.5;
const _eyeY = 62.0;
const _eyeR = 5.0;
const _grilleXs = [-10.5, 0.0, 10.5];
const _grilleTop = 9.0;
const _grilleBottom = 27.0;
const _grilleWidth = 4.5;

/// The stand: an open "U" cradle under the body, an arc of a circle
/// centered [_standCenterY] below the body's top, sweeping a little past a
/// half circle so its tips curl up beside the body.
const _standCenterY = 110.0;
const _standR = 52.0;
const _standStroke = 9.0;
const _standStart = 12 * math.pi / 180;
const _standSweep = 156 * math.pi / 180;

/// The app's companion: a capsule-bodied microphone with a three-line
/// grille, two dot eyes, and a cradle-shaped stand — drawn exactly as the
/// reference sheet shows it. Its [mood] always comes from a real session
/// event (see [moodFor]); this widget only draws it and animates it.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    required this.mood,
    required this.clock,
    this.width = 160,
    this.level,
    this.onTap,
  });

  final MascotMood mood;

  /// Seconds, ticking every frame; all motion is derived from it.
  final ValueListenable<double> clock;

  final double width;

  /// Live input loudness (0..1), read every frame while listening.
  final double Function()? level;

  final VoidCallback? onTap;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> {
  late double _moodStart = widget.clock.value;

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _moodStart = widget.clock.value;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final height = widget.width * _boxH / _boxW;
    return Semantics(
      label: 'Music Copilot companion, ${_describe(widget.mood)}',
      button: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: height,
          child: CustomPaint(
            painter: MascotPainter(
              mood: widget.mood,
              moodStart: _moodStart,
              clock: widget.clock,
              level: widget.level,
              still: still,
            ),
          ),
        ),
      ),
    );
  }
}

String _describe(MascotMood mood) => switch (mood) {
  MascotMood.idle => 'waiting',
  MascotMood.sleepy => 'dozing',
  MascotMood.tapped => 'saying hi',
  MascotMood.listening => 'listening',
  MascotMood.concentrating => 'thinking',
  MascotMood.happy => 'happy',
  MascotMood.excited => 'excited',
  MascotMood.singing => 'singing along',
  MascotMood.curious => 'unsure',
  MascotMood.surprised => 'surprised',
};

/// How the eyes are drawn in each mood, matching the sheet.
enum _Eyes { dots, wide, happyArcs, closedArcs, narrowed }

class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.mood,
    required this.moodStart,
    required this.clock,
    this.level,
    this.still = false,
  }) : super(repaint: clock);

  final MascotMood mood;
  final double moodStart;
  final ValueListenable<double> clock;
  final double Function()? level;

  /// Reduce Motion: hold each mood's resting pose.
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final now = still ? 0.0 : clock.value;
    final since = still ? 10.0 : math.max(0.0, clock.value - moodStart);
    final lvl = still ? 0.0 : (level?.call() ?? 0).clamp(0.0, 1.0);

    canvas.save();
    canvas.scale(size.width / _boxW, size.height / _boxH);
    canvas.translate(_origin.dx, _origin.dy);

    _paintStand(canvas);

    final pose = _poseFor(now, since, lvl);
    canvas.save();
    // Pivot tilts and squashes around the base of the body, so it leans
    // and bounces in its cradle rather than spinning about its middle.
    canvas.translate(0, _bodyH + pose.dy);
    canvas.rotate(pose.tilt);
    canvas.scale(pose.sx, pose.sy);
    canvas.translate(0, -_bodyH);
    _paintBody(canvas);
    if (_showsGrille) _paintGrille(canvas);
    _paintEyes(canvas, now, since);
    canvas.restore();

    _paintAccessories(canvas, now, since, lvl);
    canvas.restore();
  }

  bool get _showsGrille => switch (mood) {
    MascotMood.sleepy ||
    MascotMood.concentrating ||
    MascotMood.excited => false,
    _ => true,
  };

  _Eyes get _eyes => switch (mood) {
    MascotMood.happy => _Eyes.happyArcs,
    MascotMood.sleepy || MascotMood.singing => _Eyes.closedArcs,
    MascotMood.concentrating => _Eyes.narrowed,
    MascotMood.surprised => _Eyes.wide,
    _ => _Eyes.dots,
  };

  ({double dy, double tilt, double sx, double sy}) _poseFor(
    double now,
    double since,
    double lvl,
  ) {
    // The 4 s breath every mood rests on: scale 0.98–1.02 and a gentle
    // float — present, never static.
    final breath = math.sin(now * 2 * math.pi / 4);
    var dy = -3 * breath;
    var tilt = 0.0;
    var s = 1 + 0.02 * breath;
    var sx = s;
    var sy = s;

    switch (mood) {
      case MascotMood.idle:
        break;
      case MascotMood.sleepy:
        final slow = math.sin(now * 2 * math.pi / 6);
        dy = -1.5 * slow;
        sx = sy = 1 + 0.012 * slow;
      case MascotMood.tapped:
        // A quick squash, then a little stretch back.
        final squash =
            _bump(since, 0, 0.16) * 0.09 - _bump(since, 0.16, 0.44) * 0.05;
        sy = 1 - squash;
        sx = 1 + squash * 0.7;
        dy = -6 * _bump(since, 0.16, 0.44);
      case MascotMood.listening:
        sx = sy = 1 + 0.035 * lvl + 0.01 * breath;
        dy = -2 * breath - 3 * lvl;
      case MascotMood.concentrating:
        tilt = 0.035 * math.sin(now * 2 * math.pi * 0.5);
        dy = -1.5 * breath;
      case MascotMood.happy:
        dy = -6 * _decayingHops(since, 0.45) - 2 * breath;
      case MascotMood.excited:
        dy = -12 * _decayingHops(since, 0.36) - 2 * breath;
        final land = _bump(since % 0.36, 0.3, 0.36) * 0.05;
        sy = 1 - land;
        sx = 1 + land * 0.6;
      case MascotMood.singing:
        tilt = 0.07 * math.sin(now * 2 * math.pi * 0.8);
        dy = -3 * math.sin(now * 2 * math.pi * 1.6).abs();
      case MascotMood.curious:
        tilt = 0.21 * Curves.easeOutBack.transform(math.min(1, since / 0.5));
        dy = -2 * breath;
      case MascotMood.surprised:
        dy = -10 * _bump(since, 0, 0.32) - 2 * breath;
        sx = sy = 1 + 0.04 * _bump(since, 0, 0.32);
    }
    return (dy: dy, tilt: tilt, sx: sx, sy: sy);
  }

  void _paintStand(Canvas canvas) {
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(0, _standCenterY), radius: _standR),
      _standStart,
      _standSweep,
      false,
      Paint()
        ..color = MascotColors.body
        ..style = PaintingStyle.stroke
        ..strokeWidth = _standStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintBody(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-_bodyW / 2, 0, _bodyW, _bodyH),
        const Radius.circular(_bodyW / 2),
      ),
      Paint()..color = MascotColors.body,
    );
  }

  void _paintGrille(Canvas canvas) {
    final paint = Paint()
      ..color = MascotColors.grille
      ..strokeWidth = _grilleWidth
      ..strokeCap = StrokeCap.round;
    for (final x in _grilleXs) {
      canvas.drawLine(Offset(x, _grilleTop), Offset(x, _grilleBottom), paint);
    }
  }

  void _paintEyes(Canvas canvas, double now, double since) {
    // Changing mood swaps the eyes behind a quick blink, and the resting
    // moods blink on their own every few seconds.
    var open = since < 0.18 ? (since - 0.09).abs() / 0.09 : 1.0;
    final blinks =
        mood == MascotMood.idle ||
        mood == MascotMood.listening ||
        mood == MascotMood.tapped ||
        mood == MascotMood.curious;
    if (blinks && !still) {
      final phase = now % 4.6;
      if (phase > 4.42) open = math.min(open, (phase - 4.51).abs() / 0.09);
    }
    open = open.clamp(0.08, 1.0);

    // Curious eyes glance up and to the side, the way the sheet shows.
    final shift = mood == MascotMood.curious
        ? const Offset(4, -3)
        : Offset.zero;

    for (final side in const [-1.0, 1.0]) {
      final c = Offset(side * _eyeX, _eyeY) + shift;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, open);
      _paintEye(canvas, side);
      canvas.restore();
    }
  }

  void _paintEye(Canvas canvas, double side) {
    final fill = Paint()..color = MascotColors.eye;
    final stroke = Paint()
      ..color = MascotColors.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    switch (_eyes) {
      case _Eyes.dots:
        canvas.drawCircle(Offset.zero, _eyeR, fill);
      case _Eyes.wide:
        canvas.drawCircle(Offset.zero, _eyeR * 1.3, fill);
      case _Eyes.happyArcs:
        // "^" curves: the sheet's smiling-eyes look.
        canvas.drawPath(
          Path()
            ..moveTo(-7, 3)
            ..quadraticBezierTo(0, -7, 7, 3),
          stroke,
        );
      case _Eyes.closedArcs:
        // "‿" curves: eyes gently shut.
        canvas.drawPath(
          Path()
            ..moveTo(-7, -2)
            ..quadraticBezierTo(0, 6, 7, -2),
          stroke,
        );
      case _Eyes.narrowed:
        // A dot with its top sliced off at a slant toward the middle —
        // the sheet's focused, slightly furrowed look.
        canvas.save();
        final slant = Path()
          ..moveTo(-10, -2.5 + side * 3.6)
          ..lineTo(10, -2.5 - side * 3.6)
          ..lineTo(10, 10)
          ..lineTo(-10, 10)
          ..close();
        canvas.clipPath(slant);
        canvas.drawCircle(const Offset(0, 0.5), _eyeR * 1.45, fill);
        canvas.restore();
    }
  }

  void _paintAccessories(Canvas canvas, double now, double since, double lvl) {
    final ink = Paint()
      ..color = MascotColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case MascotMood.listening:
        _paintSoundArcs(canvas, ink, now, lvl);
      case MascotMood.happy:
        _paintTicks(canvas, ink, _happyTicks, _fadeIn(since));
      case MascotMood.excited:
        _paintTicks(canvas, ink, _excitedTicks, _fadeIn(since));
      case MascotMood.surprised:
        _paintTicks(canvas, ink, _surprisedTicks, _fadeIn(since));
      case MascotMood.tapped:
        _paintTicks(
          canvas,
          ink,
          _tapTicks,
          1 - _ramp(since, 0.25, tapReaction),
        );
      case MascotMood.singing:
        _paintNotes(canvas, now);
      case MascotMood.curious:
        _paintQuestion(canvas, ink, now, since);
      case MascotMood.idle:
      case MascotMood.sleepy:
      case MascotMood.concentrating:
        break;
    }
  }

  /// "(( ))" either side of the body, spreading and brightening with how
  /// loud the input is right now.
  void _paintSoundArcs(Canvas canvas, Paint ink, double now, double lvl) {
    for (var ring = 0; ring < 2; ring++) {
      final ripple = 0.5 + 0.5 * math.sin(now * 2 * math.pi * 1.2 - ring * 0.9);
      final reach = 60.0 + ring * 18 + lvl * 8 * (ring + 1);
      final alpha =
          (0.25 + 0.75 * lvl) * (0.55 + 0.45 * ripple) * (ring == 0 ? 1 : 0.75);
      final paint = Paint()
        ..color = MascotColors.accent.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink.strokeWidth
        ..strokeCap = StrokeCap.round;
      for (final side in const [-1.0, 1.0]) {
        final rect = Rect.fromCircle(
          center: const Offset(0, _eyeY + 8),
          radius: reach,
        );
        final start = side > 0 ? -0.42 : math.pi - 0.42;
        canvas.drawArc(rect, start, 0.84, false, paint);
      }
    }
  }

  static const _happyTicks = [
    (Offset(-58, 34), Offset(-70, 28)),
    (Offset(-61, 50), Offset(-75, 50)),
    (Offset(-58, 66), Offset(-70, 72)),
  ];
  static const _excitedTicks = [
    (Offset(-44, -4), Offset(-52, -14)),
    (Offset(-58, 14), Offset(-70, 12)),
  ];
  static const _surprisedTicks = [
    (Offset(-60, 40), Offset(-72, 34)),
    (Offset(-62, 56), Offset(-76, 56)),
    (Offset(-60, 72), Offset(-72, 78)),
  ];
  static const _tapTicks = [
    (Offset(52, 92), Offset(60, 84)),
    (Offset(60, 100), Offset(72, 98)),
    (Offset(46, 84), Offset(48, 72)),
  ];

  /// Short radiating strokes, mirrored to the right side unless they're the
  /// one-sided tap ticks.
  void _paintTicks(
    Canvas canvas,
    Paint ink,
    List<(Offset, Offset)> ticks,
    double alpha,
  ) {
    if (alpha <= 0.01) return;
    final paint = Paint()
      ..color = MascotColors.accent.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink.strokeWidth
      ..strokeCap = StrokeCap.round;
    final mirrored = !identical(ticks, _tapTicks);
    for (final (a, b) in ticks) {
      canvas.drawLine(a, b, paint);
      if (mirrored) {
        canvas.drawLine(Offset(-a.dx, a.dy), Offset(-b.dx, b.dy), paint);
      }
    }
  }

  /// Three little notes drifting up and away from the body on a loop.
  void _paintNotes(Canvas canvas, double now) {
    const period = 2.4;
    const starts = [
      (Offset(-58, 70), -1.0, 0.0),
      (Offset(56, 40), 1.0, 0.8),
      (Offset(-50, 22), -1.0, 1.6),
    ];
    for (final (origin, side, offset) in starts) {
      final p = ((now + offset) % period) / period;
      final alpha = math.sin(math.pi * p);
      final pos = origin + Offset(side * 14 * p, -34 * p);
      _paintNote(canvas, pos, 0.9 + 0.2 * (offset / 1.6), alpha, side * 0.18);
    }
  }

  void _paintNote(
    Canvas canvas,
    Offset at,
    double scale,
    double alpha,
    double lean,
  ) {
    if (alpha <= 0.02) return;
    final color = MascotColors.accent.withValues(alpha: alpha);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(lean);
    canvas.scale(scale);
    canvas.save();
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 7.5),
      Paint()..color = color,
    );
    canvas.restore();
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(4.2, -1), const Offset(4.2, -18), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(4.2, -18)
        ..quadraticBezierTo(11, -14, 10, -7),
      stroke,
    );
    canvas.restore();
  }

  /// A drawn "?" above the tilted head, bobbing slightly.
  void _paintQuestion(Canvas canvas, Paint ink, double now, double since) {
    final alpha = _fadeIn(since);
    if (alpha <= 0.01) return;
    final bob = 2 * math.sin(now * 2 * math.pi * 0.7);
    final paint = Paint()
      ..color = MascotColors.accent.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(64, -10 + bob);
    canvas.drawPath(
      Path()
        ..moveTo(-7, -6)
        ..cubicTo(-7, -15, 8, -15, 8, -6)
        ..cubicTo(8, 0, 0, 0, 0, 7),
      paint,
    );
    canvas.drawCircle(
      const Offset(0, 15),
      2.4,
      Paint()..color = MascotColors.accent.withValues(alpha: alpha),
    );
    canvas.restore();
  }

  /// 0→1→0 over [from]..[to] seconds, smooth at both ends.
  static double _bump(double t, double from, double to) {
    if (t <= from || t >= to) return 0;
    return math.sin(math.pi * (t - from) / (to - from));
  }

  /// 0→1 linear over [from]..[to] seconds.
  static double _ramp(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  static double _fadeIn(double since) =>
      Curves.easeOut.transform(_ramp(since, 0.05, 0.35));

  /// A run of hops that get smaller, like a ball settling.
  static double _decayingHops(double since, double hop) {
    final n = since / hop;
    if (n > 4) return 0;
    return math.sin(math.pi * (n % 1)).abs() *
        math.pow(0.55, n.floor()).toDouble();
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.mood != mood || old.moodStart != moodStart || old.still != still;
}
