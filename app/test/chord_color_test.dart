import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/harmonic_color.dart';
import 'package:music_copilot_app/models/harmony.dart';
import 'package:music_copilot_app/widgets/score_canvas.dart';

Chord _chord(String roman, double start, double end) => Chord(
  name: roman,
  roman: roman,
  notes: const [],
  pitchClasses: const [],
  startTime: start,
  endTime: end,
);

void main() {
  group('chordColorAt', () {
    test('returns the neutral color when no chord covers the moment', () {
      expect(chordColorAt(const [], 1.0), HarmonicColor.neutral);
      expect(chordColorAt([_chord('I', 2.0, 3.0)], 1.0), HarmonicColor.neutral);
    });

    test("returns a chord's harmonic color at a moment it covers", () {
      final chord = _chord('V', 1.0, 2.0);
      expect(chordColorAt([chord], 1.5), HarmonicColor.forRoman('V'));
    });

    test('is inclusive of a chord boundary', () {
      final chord = _chord('IV', 1.0, 2.0);
      expect(chordColorAt([chord], 1.0), HarmonicColor.forRoman('IV'));
      expect(chordColorAt([chord], 2.0), HarmonicColor.forRoman('IV'));
    });

    test('picks the first chord that covers an overlapping moment', () {
      final a = _chord('I', 0.0, 2.0);
      final b = _chord('V', 1.0, 3.0);
      expect(chordColorAt([a, b], 1.5), HarmonicColor.forRoman('I'));
    });
  });
}
