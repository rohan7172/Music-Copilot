import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/harmonic_color.dart';

void main() {
  group('HarmonicColor.degreeOf', () {
    test('parses a plain numeral', () {
      expect(HarmonicColor.degreeOf('I'), 1);
    });

    test('parses a numeral with a seventh', () {
      expect(HarmonicColor.degreeOf('V7'), 5);
    });

    test('parses a lowercase numeral with a seventh', () {
      expect(HarmonicColor.degreeOf('ii7'), 2);
    });

    test('parses a numeral with a diminished symbol', () {
      expect(HarmonicColor.degreeOf('vii°'), 7);
    });

    test('returns null for an unrecognised label', () {
      // An augmented-sixth label, which doesn't start with a roman numeral.
      expect(HarmonicColor.degreeOf('Ger6'), isNull);
    });
  });

  group('HarmonicColor.forRoman', () {
    test('is the exact tonic color at degree I (tension 0.0)', () {
      expect(HarmonicColor.forRoman('I'), const Color(0xFF8C7FD6));
    });

    test('is the exact dominant color at degree vii° (tension 1.0)', () {
      expect(HarmonicColor.forRoman('vii°'), const Color(0xFFE2724F));
    });

    test('falls back to the neutral color for an unrecognised label', () {
      expect(HarmonicColor.forRoman('Ger6'), HarmonicColor.neutral);
    });

    test('tension increases from tonic-family through to dominant-family degrees', () {
      // Not every pair is strictly ordered (iii/ii/IV are close), but the
      // broad tonic -> subdominant -> dominant progression must hold.
      final i = HarmonicColor.forRoman('I');
      final vi = HarmonicColor.forRoman('vi');
      final iv = HarmonicColor.forRoman('IV');
      final v = HarmonicColor.forRoman('V');
      double warmth(Color c) => c.r - c.b; // crude coral-vs-lavender proxy
      expect(warmth(i), lessThan(warmth(vi)));
      expect(warmth(vi), lessThan(warmth(iv)));
      expect(warmth(iv), lessThan(warmth(v)));
    });
  });
}
