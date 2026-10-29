import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../audio/waveform.dart';
import '../harmonic_color.dart';
import '../key_color.dart';
import '../models/harmony.dart';
import '../models/note.dart';
import '../note_range.dart';
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

  List<Chord> chords = const [];
  MusicKey? key;
  int? selectedChord;

  /// When [selectedChord] was last set, for a brief "grow then settle" pop
  /// on tap so it's unambiguous which chord was just tapped.
  double? chordTapStart;

  /// Current playback position (seconds) while audio is playing or paused.
  double? playhead;

  /// True while the whole recording is playing; notes light up as they sound.
  bool playingAll = false;

  /// Whether low-confidence ("faint") notes are shown at reduced opacity
  /// instead of being hidden entirely. Off by default.
  bool showFaintNotes = false;

  /// When [showFaintNotes] last flipped, so faint notes can fade in/out
  /// smoothly instead of snapping. Null means never toggled.
  double? faintToggleStart;
}

// Timings (seconds).
const _morphTime = 0.7;
const _flightTime = 0.9;
const _liveWindow = 6.0;

double settleStagger(int noteCount) =>
    math.min(0.11, 1.6 / math.max(1, noteCount));

/// When chords start appearing: once the last note is nearly home.
double chordsAppear(Scene scene) =>
    (scene.settleStart ?? 0) +
    math.max(0, scene.notes.length - 1) * settleStagger(scene.notes.length) +
    _flightTime * 0.8;

const _chordStagger = 0.08;
const _chordDraw = 0.5;

/// Where things sit on screen. Shared by the painter and the screen's hit
/// testing.
class SceneLayout {
  SceneLayout(this.size, this.scene) : fitted = fitPitchRange(scene.notes);

  final Size size;
  final Scene scene;

  /// The pitch range fitted to where notes actually are, and which note
  /// indices fall outside it — see note_range.dart.
  final FittedRange fitted;
  int get _lo => fitted.lo;
  int get _hi => fitted.hi;

  bool isOutlier(int noteIndex) => fitted.outliers.contains(noteIndex);

  /// '↑'/'↓' if note [i] sits outside the fitted range (and which way to
  /// point it at the clamped edge), else null.
  String? outlierArrow(int i) {
    final midi = scene.notes[i].midiPitch;
    if (midi > _hi) return '↑';
    if (midi < _lo) return '↓';
    return null;
  }

  // Left margin leaves room for the pitch axis.
  double get left => 52;
  double get right => size.width - 28;
  double get width => right - left;
  double get waveY => size.height * 0.70;
  double get waveAmp => math.min(size.height * 0.11, 72);
  double get laneTop => size.height * 0.14;

  // Chords float as small tabs well clear of the waveform now, rather than
  // occupying a dedicated band, so the lane always gets this space.
  double get laneBottom => size.height * 0.58;

  /// Centre of a chord tab — clearly clear of the waveform's peak, not
  /// grazing it.
  double get chordY => waveY - waveAmp - 34;
  static const chordHeight = 22.0;
  static const chordTabWidth = 58.0;

  /// A small pill centered on the chord's time-midpoint — a fixed-size tab,
  /// not a bar stretched across its duration (which read as a stray line).
  Rect chordRect(Chord c) => Rect.fromCenter(
        center: Offset(xForTime((c.startTime + c.endTime) / 2), chordY),
        width: chordTabWidth,
        height: chordHeight,
      );

  double get duration => scene.waveform?.duration ?? 1;

  double xForTime(double t) => left + (t / duration).clamp(0.0, 1.0) * width;

  /// Clamped to the lane's top/bottom edge for a pitch outside the fitted
  /// range, rather than stretching the lane to reach it.
  double yForMidi(int midi) {
    if (midi > _hi) return laneTop;
    if (midi < _lo) return laneBottom;
    return laneBottom - (midi - _lo) / (_hi - _lo) * (laneBottom - laneTop);
  }

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
        _paintRecorded(canvas, layout, now);
      case Phase.settled:
        _paintAmbient(canvas, layout, now);
        _paintRecorded(canvas, layout, now);
    }
  }

  // --- Ambient atmosphere -----------------------------------------------------

  static const _pulseDuration = 1.4;

  /// A sense of musical atmosphere behind everything else, in the key's own
  /// color (see KeyColor — an identity, not a harmonic-function reading):
  /// one soft pulse across the whole screen as the piece "arrives," settling
  /// into a slow, organic drift that never quite repeats.
  void _paintAmbient(Canvas canvas, SceneLayout l, double now) {
    final key = scene.key;
    final settleStart = scene.settleStart;
    if (key == null || settleStart == null) return;
    final color = KeyColor.forTonic(key.tonic);
    final center = Offset(l.size.width / 2, l.size.height / 2);
    final diagonal = l.size.shortestSide + l.size.longestSide;
    final t = now - settleStart;

    // The one-shot pulse: expands past the edges of the screen while fading.
    final pulseQ = (t / _pulseDuration).clamp(0.0, 1.0);
    if (pulseQ < 1) {
      final radius = diagonal * 0.45 * Curves.easeOut.transform(pulseQ);
      final alpha = 0.45 * (1 - Curves.easeIn.transform(pulseQ));
      _paintGlow(canvas, center, radius, color.withValues(alpha: alpha));
    }

    // The ambient drift: always present once settled, low and slow, its
    // center meandering so it never looks mechanical or like it's looping.
    final driftCenter = center +
        Offset(
          math.sin(t * 0.07) * l.size.width * 0.15 + math.sin(t * 0.031) * l.size.width * 0.08,
          math.cos(t * 0.05) * l.size.height * 0.12 + math.cos(t * 0.043) * l.size.height * 0.07,
        );
    _paintGlow(canvas, driftCenter, diagonal * 0.4, color.withValues(alpha: 0.1));
  }

  /// 0 before settling, rising to 1 over the same span as the ambient
  /// pulse — how far the waveform has gone from plain ink toward the key's
  /// bold color.
  double _waveformColorT(double now) {
    final settleStart = scene.settleStart;
    if (scene.phase != Phase.settled || scene.key == null || settleStart == null) return 0;
    return ((now - settleStart) / _pulseDuration).clamp(0.0, 1.0);
  }

  /// The waveform's own color: ink-gray until settled, then crossfading to
  /// the key's bold, fully-saturated color (not a faint tint of it) over
  /// the same span as the ambient pulse — the splash visually "paints" the
  /// waveform as it passes over it.
  Color _waveformBaseColor(double now, double t) {
    final key = scene.key;
    if (key == null) return _ink;
    return Color.lerp(_ink, KeyColor.forTonicVivid(key.tonic), t)!;
  }

  void _paintGlow(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 0 || color.a <= 0) return;
    final paint = Paint()
      ..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]);
    canvas.drawCircle(center, radius, paint);
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
    // As the waveform's color arrives, it also grows bolder — a faint ink
    // wash becomes a solid, fully-saturated ribbon, not just a tinted gray.
    final colorT = _waveformColorT(now);
    final waveColor = _waveformBaseColor(now, colorT);
    final fillAlpha = ui.lerpDouble(0.10, 0.4, colorT)!;
    final strokeAlpha = ui.lerpDouble(0.55, 0.95, colorT)!;
    canvas.drawPath(path, Paint()..color = waveColor.withValues(alpha: fillAlpha * morph));
    final stroke = _strokePaint(waveColor.withValues(alpha: strokeAlpha * morph))
      ..strokeWidth = ui.lerpDouble(1, 1.6, colorT)!;
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
    if (scene.phase == Phase.settled) {
      _paintPitchAxis(canvas, l, now);
      _paintNotes(canvas, l, now);
      _paintChords(canvas, l, now);
      _paintKey(canvas, l, now);
    }
  }

  /// Pitch names once, down the left edge, piano-roll style — replaces a
  /// name floating over every note head. Only pitches actually played (and
  /// within the fitted range) get a label; it fades in with that pitch's
  /// lane.
  void _paintPitchAxis(Canvas canvas, SceneLayout l, double now) {
    final notes = scene.notes;
    final start = scene.settleStart ?? now;
    final stagger = settleStagger(notes.length);
    final pitchNames = <int, String>{};
    final arrival = <int, double>{};
    for (var i = 0; i < notes.length; i++) {
      if (l.isOutlier(i)) continue;
      final note = notes[i];
      final faintVis = _faintVisibility(note, now);
      if (faintVis <= 0) continue;
      pitchNames.putIfAbsent(note.midiPitch, () => note.pitch);
      final p = ((now - start - i * stagger) / _flightTime).clamp(0.0, 1.0);
      final a = ((p - 0.7) / 0.3).clamp(0.0, 1.0);
      arrival[note.midiPitch] = math.max(arrival[note.midiPitch] ?? 0, a * faintVis);
    }
    pitchNames.forEach((midi, pitchName) {
      final a = arrival[midi] ?? 0;
      if (a <= 0) return;
      _paintAxisLabel(canvas, l.yForMidi(midi), pitchName, a);
    });
  }

  static final _pitchNameRe = RegExp(r'^([A-Ga-g][#b]?)(-?\d+)$');

  /// Note name with its octave rendered smaller and dropped, for a rough
  /// subscript (e.g. "A#" then a smaller "4").
  void _paintAxisLabel(Canvas canvas, double y, String pitchName, double alpha) {
    final match = _pitchNameRe.firstMatch(pitchName);
    final letter = match?.group(1) ?? pitchName;
    final octave = match?.group(2) ?? '';
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: letter,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              color: _ink.withValues(alpha: 0.6 * alpha),
            ),
          ),
          if (octave.isNotEmpty)
            TextSpan(
              text: octave,
              style: TextStyle(fontSize: 8, color: _ink.withValues(alpha: 0.45 * alpha)),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(8, y - painter.height / 2));
  }

  /// Chords draw themselves in, left to right, once the notes have landed:
  /// a band per chord between the notes and the waveform they came from.
  void _paintChords(Canvas canvas, SceneLayout l, double now) {
    final start = chordsAppear(scene);
    final playhead = scene.playhead;
    for (var j = 0; j < scene.chords.length; j++) {
      final chord = scene.chords[j];
      final q = ((now - start - j * _chordStagger) / _chordDraw).clamp(0.0, 1.0);
      if (q <= 0) continue;
      final sounding = scene.playingAll &&
          playhead != null &&
          playhead >= chord.startTime &&
          playhead <= chord.endTime;
      final lit = scene.selectedChord == j || sounding;
      final dim = scene.selectedChord == null && scene.selected == null || lit ? 1.0 : 0.45;

      final full = l.chordRect(chord);

      // Pops in as it reveals (overshooting slightly), then pops again,
      // briefly bigger, right when tapped — so it's unmistakable which
      // chord was just selected.
      final revealScale = 0.5 + 0.5 * Curves.easeOutBack.transform(q);
      var tapScale = 1.0;
      if (scene.selectedChord == j) {
        final tapStart = scene.chordTapStart;
        if (tapStart != null) {
          final tapT = Curves.easeOut.transform(((now - tapStart) / 0.25).clamp(0.0, 1.0));
          tapScale = 1.0 + 0.3 * (1 - tapT);
        }
      }
      final scale = revealScale * tapScale;
      final rect = Rect.fromCenter(
        center: full.center,
        width: full.width * scale,
        height: full.height * scale,
      );
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
      final color = HarmonicColor.forRoman(chord.roman);

      // As this chord reveals itself, a small pulse glows around each of
      // its notes — the progression's movement (I, then IV, then V, ...)
      // felt around the notes themselves, not across the whole screen.
      final pulse = math.sin(math.pi * q.clamp(0.0, 0.6) / 0.6);
      if (pulse > 0) {
        for (final note in scene.notes) {
          if (!chord.contains(note)) continue;
          _paintGlow(canvas, l.target(note), 45 * pulse, color.withValues(alpha: 0.18 * pulse));
        }
      }

      // Paper first, so it reads as a solid card, not a faint outline.
      canvas.drawRRect(shape, Paint()..color = Palette.paper.withValues(alpha: q));
      canvas.drawRRect(
        shape,
        Paint()..color = color.withValues(alpha: (lit ? 0.32 : 0.14) * q * dim),
      );
      canvas.drawRRect(
        shape,
        _strokePaint(color.withValues(alpha: (lit ? 0.85 : 0.4) * q * dim))
          ..strokeWidth = lit ? 1.4 : 1,
      );

      final textAlpha = ((q - 0.4) / 0.6).clamp(0.0, 1.0) * dim;
      if (textAlpha <= 0) continue;
      final name = TextSpan(
        text: chord.name,
        style: TextStyle(
          fontSize: lit ? 11 : 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: _ink.withValues(alpha: 0.85 * textAlpha),
        ),
      );
      final roman = TextSpan(
        text: '  ${chord.roman}',
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.3,
          color: _ink.withValues(alpha: 0.5 * textAlpha),
        ),
      );
      // Name and numeral if they fit, else just the name, else nothing.
      for (final label in [TextSpan(children: [name, roman]), name]) {
        final painter = TextPainter(text: label, textDirection: TextDirection.ltr)
          ..layout();
        if (painter.width <= full.width - 8) {
          painter.paint(
            canvas,
            Offset(full.center.dx - painter.width / 2, full.center.dy - painter.height / 2),
          );
          break;
        }
      }
    }
  }

  /// The detected key, quietly in the corner once the chords arrive.
  void _paintKey(Canvas canvas, SceneLayout l, double now) {
    final key = scene.key;
    if (key == null) return;
    final a = ((now - chordsAppear(scene)) / 0.6).clamp(0.0, 1.0);
    if (a <= 0) return;
    // The key name itself takes on a dark shade of the key's own color as
    // it arrives, rather than staying plain ink.
    final nameColor = Color.lerp(_ink, KeyColor.forTonicDark(key.tonic), _waveformColorT(now))!;
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'KEY  ',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              color: _ink.withValues(alpha: 0.35 * a),
            ),
          ),
          TextSpan(
            text: key.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: nameColor.withValues(alpha: 0.75 * a),
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(l.left, l.size.height * 0.06));
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

  static const _faintFadeDuration = 0.5;

  /// 0..1: how visible a faint (low-confidence) note currently is, smoothly
  /// fading in/out around when the toggle last flipped. A normal-confidence
  /// note is always fully visible.
  double _faintVisibility(Note note, double now) {
    if (note.confidence >= noteConfidenceThreshold) return 1.0;
    final toggleStart = scene.faintToggleStart;
    final progress =
        toggleStart == null ? 1.0 : ((now - toggleStart) / _faintFadeDuration).clamp(0.0, 1.0);
    return scene.showFaintNotes ? progress : 1 - progress;
  }

  void _paintNotes(Canvas canvas, SceneLayout l, double now) {
    final notes = scene.notes;
    final start = scene.settleStart ?? now;
    final stagger = settleStagger(notes.length);
    final selected = scene.selected;
    final chordIndex = scene.selectedChord;
    final chord = chordIndex == null ? null : scene.chords[chordIndex];

    // Lane hairlines appear as each pitch first lands.
    final landed = <int, double>{};
    for (var i = 0; i < notes.length; i++) {
      if (_faintVisibility(notes[i], now) <= 0 || l.isOutlier(i)) continue;
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

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final faintVis = _faintVisibility(note, now);
      if (faintVis <= 0) continue;
      final p = ((now - start - i * stagger) / _flightTime).clamp(0.0, 1.0);
      if (p <= 0) continue;

      final inChord = chord != null && chord.contains(note);
      final focused = selected == null && chord == null;
      // A faint note settles at half strength once fully faded in, rather
      // than full strength, so it still reads as lower-confidence.
      final faintFactor = note.confidence < noteConfidenceThreshold ? 0.5 * faintVis : 1.0;
      final dim = (focused || selected == i || inChord ? 1.0 : 0.3) * faintFactor;

      // The color of whichever chord this note sounds within, regardless of
      // selection; a note outside any detected chord gets a neutral color.
      Chord? owner;
      for (final c in scene.chords) {
        if (c.contains(note)) {
          owner = c;
          break;
        }
      }
      final noteColor = owner == null ? HarmonicColor.neutral : HarmonicColor.forRoman(owner.roman);
      final playhead = scene.playhead;
      final sounding = scene.playingAll &&
          playhead != null &&
          playhead >= note.startTime &&
          playhead <= note.endTime;
      final lit = selected == i || sounding || inChord;
      final conf = (0.4 + 0.6 * (note.confidence / 0.8).clamp(0.0, 1.0)) * dim;
      final from = l.origin(note);
      final to = l.target(note);
      final side = i.isEven ? 1.0 : -1.0;
      final control = Offset(from.dx + side * 28, (from.dy + to.dy) / 2);
      Offset along(double e) => _bezier(from, control, to, e);

      final e = Curves.easeOutCubic.transform(p);
      final arrive = Curves.easeOut.transform(((p - 0.7) / 0.3).clamp(0.0, 1.0));
      final outlier = l.isOutlier(i);

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
        canvas.drawPath(segment, Paint()..color = noteColor.withValues(alpha: tint * arrive));

        // Thread tying the note back to where it was heard — only while
        // it's still landing, or while selected/playing; hidden otherwise
        // so it doesn't clutter the settled view.
        final threadAlpha = lit ? 0.25 * arrive : (arrive >= 1.0 ? 0.0 : 0.06 * dim * arrive);
        if (threadAlpha > 0) {
          canvas.drawLine(
            Offset(to.dx, from.dy),
            Offset(to.dx, to.dy + 6),
            Paint()
              ..color = _ink.withValues(alpha: threadAlpha)
              ..strokeWidth = 1,
          );
        }

        if (!outlier) {
          // Duration pill growing out of the head.
          const pillHalf = 3.5;
          final endX = to.dx + (l.xForTime(note.endTime) - to.dx) * arrive;
          final pillRect = Rect.fromLTRB(
            to.dx,
            to.dy - pillHalf,
            math.max(endX, to.dx + pillHalf * 2),
            to.dy + pillHalf,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(pillRect, Radius.circular(pillHalf)),
            Paint()..color = noteColor.withValues(alpha: 0.28 * conf),
          );

          // While its slice plays, the pill fills in brighter.
          if (lit && playhead != null && playhead > note.startTime) {
            final px = math.min(l.xForTime(playhead), l.xForTime(note.endTime));
            final filledRect = Rect.fromLTRB(
              to.dx,
              to.dy - pillHalf,
              math.max(px, to.dx + pillHalf * 2),
              to.dy + pillHalf,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(filledRect, Radius.circular(pillHalf)),
              Paint()..color = noteColor.withValues(alpha: 0.85),
            );
          }
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
            Paint()..color = noteColor.withValues(alpha: 0.35 * (1 - k / 7) * conf),
          );
        }
      }

      // Head: grows as it travels, with a small pop on landing — the
      // pill's brighter starting cap once settled.
      final pop = p > 0.8 ? math.sin(math.pi * (p - 0.8) / 0.2) : 0.0;
      final radius = (2.2 + 2.6 * e) * (1 + 0.35 * pop);
      final head = along(e);
      canvas.drawCircle(head, radius, Paint()..color = noteColor.withValues(alpha: conf));
      if (lit) {
        canvas.drawCircle(
          head,
          radius + 5,
          _strokePaint(noteColor.withValues(alpha: 0.6))..strokeWidth = 1.2,
        );
      }

      // A note outside the fitted pitch range sits clamped at the lane
      // edge with a small arrow + name instead of a normal pill, so it
      // doesn't stretch every lane to reach it.
      if (outlier && arrive > 0.3) {
        final arrow = l.outlierArrow(i) ?? '';
        final painter = TextPainter(
          text: TextSpan(
            text: '$arrow ${note.pitch}',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.4,
              color: _ink.withValues(alpha: 0.6 * arrive * dim),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(to.dx - painter.width / 2, to.dy + (arrow == '↑' ? 8 : -18)));
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
