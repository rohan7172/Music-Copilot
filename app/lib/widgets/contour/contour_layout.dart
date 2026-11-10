import 'dart:math' as math;
import 'dart:ui';

import '../../models/note.dart';
import '../../note_range.dart';

const _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];

/// "C4" for MIDI 60.
String midiName(int midi) => '${_noteNames[midi % 12]}${midi ~/ 12 - 1}';

final _chordSymbol = RegExp(r'^([A-G][#b♯♭]?)(.*)$');

/// A chord's name reduced to what a very narrow pill can hold: its root and
/// whether it's minor, diminished or augmented. "Em7" is "Em", "Cmaj7" is "C".
String shortChordName(String symbol) {
  final match = _chordSymbol.firstMatch(symbol);
  if (match == null) return symbol;
  final root = match[1]!;
  final quality = match[2]!;
  if (quality.startsWith('maj')) return root;
  if (quality.startsWith('m7b5') || quality.startsWith('dim')) return '$root°';
  if (quality.startsWith('aug')) return '$root+';
  if (quality.startsWith('m')) return '${root}m';
  return root;
}

/// What to write in one chord's ribbon pill.
class RibbonLabel {
  const RibbonLabel(this.text, this.fontSize);

  final String text;
  final double fontSize;
}

const _ribbonFullSizes = [9.5, 8.5, 7.5];
const _ribbonShortSizes = [8.5, 7.5];
const _ribbonLabelPad = 2.0;

/// The label for each of [rects]' chords, all in one style so the ribbon
/// reads evenly: full names at the largest size where every one fits, then
/// short names. When even those can't all fit (a long song's many bars), none
/// is labelled: naming every other chord would make G-D-Em-C read as G-Em.
/// [measure] is the width of a text at a font size.
List<RibbonLabel?> ribbonLabels(
  List<String> symbols,
  List<Rect> rects,
  double Function(String text, double fontSize) measure,
) {
  List<RibbonLabel>? allAt(List<String> names, double size) {
    for (var i = 0; i < names.length; i++) {
      if (measure(names[i], size) + _ribbonLabelPad > rects[i].width) {
        return null;
      }
    }
    return [for (final name in names) RibbonLabel(name, size)];
  }

  for (final size in _ribbonFullSizes) {
    final labels = allAt(symbols, size);
    if (labels != null) return labels;
  }
  final short = [for (final s in symbols) shortChordName(s)];
  for (final size in _ribbonShortSizes) {
    final labels = allAt(short, size);
    if (labels != null) return labels;
  }

  return List.filled(symbols.length, null);
}

/// Where everything sits in the vocal-contour roll: time runs left to
/// right, pitch bottom to top, each note a pill on its own pitch lane.
/// Pure geometry, shared by the painter and tap handling, and unit-tested.
class ContourLayout {
  ContourLayout({
    required this.size,
    required this.notes,
    required this.duration,
    this.lanes,
    this.overlay = const [],
  }) : fitted = fitPitchRange([...notes, ...overlay]);

  /// A second line drawn with the notes (a harmony), included when fitting
  /// the pitch range so both lines are in view.
  final List<Note> overlay;

  /// Fixed rows instead of a pitch range, lowest first — e.g. a drum part's
  /// kick, snare and hi-hat, spread evenly rather than by their (arbitrary)
  /// drum-map note numbers.
  final List<int>? lanes;

  final Size size;

  /// Notes to draw (already filtered to the confident ones).
  final List<Note> notes;

  /// Length of the take, seconds.
  final double duration;

  /// The pitch range fitted to where the notes actually are — see
  /// note_range.dart; notes outside it pin to the top or bottom edge.
  final FittedRange fitted;

  /// Room on the left for the pitch labels.
  static const labelGutter = 30.0;

  /// The band above the roll where the chosen progression's chords sit,
  /// each pill spanning its bar.
  static const ribbonHeight = 30.0;
  static const rightPad = 10.0;
  static const verticalPad = 10.0;
  static const pillHeight = 22.0;
  static const minPillWidth = 10.0;
  static const drumTickWidth = 4.0;

  /// When notes are sparse enough to each carry their name, pills are at
  /// least this wide so the name fits.
  static const labelPillWidth = 34.0;

  /// The narrowest pill in this roll: wide enough for a name when there's
  /// room for every note to have one, otherwise just wide enough to tap.
  double get pillFloor => lanes != null
      // Named lanes (drums) say what each hit is: hits are thin ticks, so a
      // busy hi-hat still reads as separate strokes.
      ? drumTickWidth
      : notes.length * (labelPillWidth + 4) <= width
      ? labelPillWidth
      : minPillWidth;

  double get left => labelGutter;
  double get right => size.width - rightPad;
  double get width => math.max(1, right - left);
  double get top => ribbonHeight + verticalPad + pillHeight / 2;
  double get bottom => size.height - verticalPad - pillHeight / 2;

  double xForTime(double t) =>
      left + (duration <= 0 ? 0 : (t / duration).clamp(0.0, 1.0)) * width;

  double timeForX(double x) => ((x - left) / width).clamp(0.0, 1.0) * duration;

  double yForMidi(int midi) {
    final rows = lanes;
    if (rows != null) {
      final index = rows.indexOf(midi);
      if (rows.length < 2 || index < 0) return (top + bottom) / 2;
      return bottom - index / (rows.length - 1) * (bottom - top);
    }
    final lo = fitted.lo;
    final hi = fitted.hi;
    if (midi >= hi) return top;
    if (midi <= lo) return bottom;
    return bottom - (midi - lo) / (hi - lo) * (bottom - top);
  }

  /// The pill for note [i], at least [minPillWidth] wide so a very short
  /// note is still something you can see and tap.
  Rect pill(int i) {
    final n = notes[i];
    final x0 = xForTime(n.startTime);
    final x1 = lanes != null
        ? x0 + pillFloor
        : math.max(xForTime(n.endTime), x0 + pillFloor);
    final y = yForMidi(n.midiPitch);
    return Rect.fromLTRB(
      x0,
      y - pillHeight / 2,
      math.min(x1, right),
      y + pillHeight / 2,
    );
  }

  /// A chord's pill in the ribbon, clipped to the roll's time span.
  Rect chordRect(double start, double end) {
    final x0 = xForTime(start) + 1.5;
    final x1 = xForTime(end) - 1.5;
    return Rect.fromLTRB(x0, 4, math.max(x1, x0 + 4), ribbonHeight - 4);
  }

  /// Index of the chord whose ribbon pill is under [p], or null.
  int? hitChord(Offset p, List<(double, double)> spans) {
    if (p.dy > ribbonHeight + 4) return null;
    for (var i = 0; i < spans.length; i++) {
      final (start, end) = spans[i];
      if (chordRect(start, end).inflate(3).contains(p)) return i;
    }
    return null;
  }

  /// Up to five evenly spaced pitches to rule and label, spanning the
  /// fitted range, highest first.
  List<int> gridPitches() {
    if (lanes != null) return lanes!.reversed.toList();
    final lo = fitted.lo;
    final hi = fitted.hi;
    final step = math.max(1, ((hi - lo) / 4).ceil());
    return [for (var m = hi; m >= lo; m -= step) m];
  }

  /// The note whose pill is under [p] (with a little slop for fingers),
  /// nearest center first; null if none.
  int? hitNote(Offset p) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < notes.length; i++) {
      final r = pill(i).inflate(6);
      if (!r.contains(p)) continue;
      final d = (r.center - p).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// The melody thread: one point per note, joining each note to the next
  /// one that starts after it ends (so stacked, simultaneous notes don't
  /// zigzag), broken wherever there's more than [maxGap] seconds of rest.
  List<List<Offset>> thread({double maxGap = 1.0}) {
    if (lanes != null) return const []; // no melodic line through drum hits
    final order = [for (var i = 0; i < notes.length; i++) i]
      ..sort((a, b) => notes[a].startTime.compareTo(notes[b].startTime));
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    Note? previous;
    for (final i in order) {
      final n = notes[i];
      if (previous != null && n.startTime < previous.endTime - 0.05) continue;
      if (previous != null && n.startTime - previous.endTime > maxGap) {
        if (run.length > 1) runs.add(run);
        run = <Offset>[];
      }
      final r = pill(i);
      run.add(Offset(r.left + math.min(r.width / 2, 10), r.center.dy));
      previous = n;
    }
    if (run.length > 1) runs.add(run);
    return runs;
  }
}
