import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/widgets/contour/contour_layout.dart';

/// Roughly how wide real text comes out: 0.6em per character.
double measure(String text, double fontSize) => text.length * fontSize * 0.6;

/// [count] pills side by side, each [width] wide, 3 apart.
List<Rect> pills(int count, double width) => [
  for (var i = 0; i < count; i++) Rect.fromLTWH(i * (width + 3), 4, width, 22),
];

void main() {
  group('shortChordName', () {
    test('keeps the root and whether the chord is minor', () {
      expect(shortChordName('Cmaj7'), 'C');
      expect(shortChordName('Em7'), 'Em');
      expect(shortChordName('Em'), 'Em');
      expect(shortChordName('G7'), 'G');
      expect(shortChordName('Gsus4'), 'G');
      expect(shortChordName('F#m7'), 'F#m');
      expect(shortChordName('Bbmaj7'), 'Bb');
    });

    test('keeps diminished and augmented, which change the sound most', () {
      expect(shortChordName('Bdim'), 'B°');
      expect(shortChordName('Bm7b5'), 'B°');
      expect(shortChordName('Caug'), 'C+');
    });

    test('leaves anything it does not recognise alone', () {
      expect(shortChordName('N.C.'), 'N.C.');
    });
  });

  group('ribbonLabels', () {
    test('uses full names at full size when every one fits', () {
      final labels = ribbonLabels(['C', 'F', 'G'], pills(3, 40), measure);
      expect(labels.map((l) => l?.text), ['C', 'F', 'G']);
      expect(labels.map((l) => l?.fontSize), everyElement(9.5));
    });

    test('shrinks the whole ribbon together rather than one chord', () {
      final labels = ribbonLabels(['C', 'Cmaj7'], pills(2, 28), measure);
      expect(labels.map((l) => l?.text), ['C', 'Cmaj7']);
      expect(labels.map((l) => l?.fontSize), everyElement(8.5));
    });

    test('shortens every name once full names cannot fit', () {
      final labels = ribbonLabels(['G', 'Em7'], pills(2, 13), measure);
      expect(labels.map((l) => l?.text), ['G', 'Em']);
    });

    test('never leaves a pill blank while short names fit', () {
      final symbols = ['G', 'D', 'Em', 'C'];
      final labels = ribbonLabels(symbols, pills(4, 13), measure);
      expect(labels, everyElement(isNotNull));
    });

    test('labels nothing once any short name cannot fit', () {
      // Naming only some would misstate the progression.
      final labels = ribbonLabels(['G', 'D', 'Em', 'C'], pills(4, 7), measure);
      expect(labels, everyElement(isNull));
    });

    test('an empty ribbon has no labels', () {
      expect(ribbonLabels(const [], const [], measure), isEmpty);
    });
  });
}
