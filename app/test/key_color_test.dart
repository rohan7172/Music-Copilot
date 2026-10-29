import 'package:flutter/material.dart';
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

  group('KeyColor.forTonicVivid', () {
    test('is more saturated than the soft forTonic color for the same key', () {
      final soft = HSLColor.fromColor(KeyColor.forTonic('G'));
      final vivid = HSLColor.fromColor(KeyColor.forTonicVivid('G'));

      expect(vivid.saturation, greaterThan(soft.saturation));
    });

    test('keeps the same hue as forTonic, so it reads as the same key', () {
      final soft = HSLColor.fromColor(KeyColor.forTonic('D'));
      final vivid = HSLColor.fromColor(KeyColor.forTonicVivid('D'));

      // A little slack: converting HSL -> 8-bit RGB -> HSL isn't lossless.
      expect(vivid.hue, closeTo(soft.hue, 1.0));
    });

    test('falls back gracefully for an unrecognised tonic', () {
      expect(() => KeyColor.forTonicVivid('H'), returnsNormally);
    });
  });

  group('KeyColor.forTonicDark', () {
    test('is darker (lower lightness) than forTonic for the same key', () {
      final soft = HSLColor.fromColor(KeyColor.forTonic('E'));
      final dark = HSLColor.fromColor(KeyColor.forTonicDark('E'));

      expect(dark.lightness, lessThan(soft.lightness));
    });

    test('keeps the same hue as forTonic, so it reads as the same key', () {
      final soft = HSLColor.fromColor(KeyColor.forTonic('A'));
      final dark = HSLColor.fromColor(KeyColor.forTonicDark('A'));

      // A little slack: converting HSL -> 8-bit RGB -> HSL isn't lossless.
      expect(dark.hue, closeTo(soft.hue, 1.0));
    });

    test('falls back gracefully for an unrecognised tonic', () {
      expect(() => KeyColor.forTonicDark('H'), returnsNormally);
    });
  });
}
