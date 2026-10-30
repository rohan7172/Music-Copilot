import 'dart:math' as math;

import 'models/note.dart';

/// A pitch range fitted to where notes actually are, plus which notes (by
/// index into the list passed to [fitPitchRange]) fall outside it.
class FittedRange {
  FittedRange({required this.lo, required this.hi, required this.outliers});

  final int lo;
  final int hi;
  final Set<int> outliers;
}

/// Below this, a note is "faint": excluded from range-fitting, and hidden
/// from the canvas entirely unless the user asks to see faint notes too.
const noteConfidenceThreshold = 0.4;

const _maxCompactSpan = 18;
const _minSpan = 12;
const _outlierPad = 3;
const _coverage = 0.9;

/// Fits lane bounds to the densest span of confident notes rather than the
/// raw min/max, so a handful of low-confidence stray detections (or one
/// genuine but far-flung note) don't stretch every lane to cover them.
/// Notes outside the fitted range are returned as outliers rather than
/// dropped, so the caller can still represent them (e.g. clamped to an
/// edge with a marker) instead of hiding them.
FittedRange fitPitchRange(List<Note> notes) {
  if (notes.isEmpty) return FittedRange(lo: 60, hi: 72, outliers: {});

  final confidentPitches = [
    for (final n in notes)
      if (n.confidence >= noteConfidenceThreshold) n.midiPitch,
  ];
  final pitches = confidentPitches.isEmpty
      ? [for (final n in notes) n.midiPitch]
      : confidentPitches;

  var lo = pitches.reduce(math.min) - 1;
  var hi = pitches.reduce(math.max) + 1;

  if (hi - lo > _maxCompactSpan) {
    final sorted = [...pitches]..sort();
    final need = math.max(1, (sorted.length * _coverage).ceil());
    var bestLo = sorted.first;
    var bestHi = sorted.last;
    var bestSpan = bestHi - bestLo;
    for (var i = 0; i + need - 1 < sorted.length; i++) {
      final span = sorted[i + need - 1] - sorted[i];
      if (span < bestSpan) {
        bestSpan = span;
        bestLo = sorted[i];
        bestHi = sorted[i + need - 1];
      }
    }
    lo = bestLo - _outlierPad;
    hi = bestHi + _outlierPad;
  }

  final floorPad = math.max(0, _minSpan - (hi - lo));
  lo -= floorPad ~/ 2;
  hi += floorPad - floorPad ~/ 2;

  final outliers = <int>{
    for (var i = 0; i < notes.length; i++)
      if (notes[i].midiPitch < lo || notes[i].midiPitch > hi) i,
  };

  return FittedRange(lo: lo, hi: hi, outliers: outliers);
}
