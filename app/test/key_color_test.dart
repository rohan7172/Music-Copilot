import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/key_color.dart';

void main() {
  group('KeyColor.forTonic', () {
    test('gives different keys different colors', () {
      expect(KeyColor.forTonic('C'), isNot(KeyColor.forTonic('G')));
      expect(KeyColor.forTonic('C'), isNot(KeyColor.forTonic('F#')));
    });

    test('is the same for sharp and flat spellings of the same pitch class', () {
      expect(KeyColor.forTonic('C#'), KeyColor.forTonic('Db'));
      expect(KeyColor.forTonic('F#'), KeyColor.forTonic('Gb'));
      expect(KeyColor.forTonic('A#'), KeyColor.forTonic('Bb'));
    });

    test('is consistent for the same tonic across calls', () {
      expect(KeyColor.forTonic('G'), KeyColor.forTonic('G'));
    });

    test('falls back gracefully for an unrecognised tonic', () {
      expect(() => KeyColor.forTonic('H'), returnsNormally);
    });
  });
}
