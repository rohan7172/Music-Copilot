import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/note.dart';
import 'package:music_copilot_app/note_range.dart';

Note note(int midiPitch, double confidence) {
  return Note(pitch: 'x', midiPitch: midiPitch, startTime: 0, endTime: 1, confidence: confidence);
}

void main() {
  group('fitPitchRange', () {
    test('a compact note set keeps its full span, padded to the floor', () {
      final notes = [note(60, 0.7), note(64, 0.7), note(67, 0.7)];
      final range = fitPitchRange(notes);

      expect(range.lo, lessThanOrEqualTo(60));
      expect(range.hi, greaterThanOrEqualTo(67));
      expect(range.outliers, isEmpty);
    });

    test('a tiny range is still padded to the 12-semitone floor', () {
      final notes = [note(60, 0.7), note(60, 0.7)];
      final range = fitPitchRange(notes);

      expect(range.hi - range.lo, greaterThanOrEqualTo(12));
    });

    test('a pitch far from a dense cluster is excluded and flagged, regardless of confidence', () {
      final notes = [
        for (var i = 0; i < 9; i++) note(62, 0.7),
        note(85, 0.7),
      ];
      final range = fitPitchRange(notes);

      expect(range.hi, lessThan(85));
      expect(range.outliers, contains(9));
    });

    test('a low-confidence note does not stretch the range even if not a literal outlier', () {
      final notes = [
        for (var i = 0; i < 9; i++) note(62, 0.7),
        note(85, 0.2), // below the confidence threshold
      ];
      final range = fitPitchRange(notes);

      expect(range.hi, lessThan(85));
      expect(range.outliers, contains(9));
    });

    test('an empty note list returns a sensible default range', () {
      final range = fitPitchRange(const []);

      expect(range.hi - range.lo, greaterThanOrEqualTo(12));
      expect(range.outliers, isEmpty);
    });
  });
}
