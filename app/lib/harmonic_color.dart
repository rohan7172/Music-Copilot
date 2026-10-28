import 'package:flutter/material.dart';

/// Maps a chord's scale degree to a color along a tonic<->dominant
/// "temperature" axis: lavender at rest (tonic), coral under tension
/// (dominant), blending smoothly through the degrees in between.
class HarmonicColor {
  static const _tonic = Color(0xFF8C7FD6);
  static const _dominant = Color(0xFFE2724F);

  /// Tension per scale degree: 0 is most restful, 1 is most tense.
  static const _tension = {1: 0.0, 6: 0.15, 3: 0.35, 2: 0.55, 4: 0.6, 5: 0.9, 7: 1.0};

  static const _neutralTension = 0.3;

  /// The color for a chord whose scale degree isn't recognised.
  static Color get neutral => Color.lerp(_tonic, _dominant, _neutralTension)!;

  static final _romanRe = RegExp(r'^[#b-]*([IVXivx]+)');
  static const _degreeNames = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7};

  /// The scale degree (1-7) [roman] names, or null if unrecognised.
  /// Mirrors backend/app/explain.py's `_scale_degree`.
  static int? degreeOf(String roman) {
    final match = _romanRe.firstMatch(roman);
    if (match == null) return null;
    return _degreeNames[match.group(1)!.toUpperCase()];
  }

  /// The color for [roman]'s scale degree.
  static Color forRoman(String roman) {
    final degree = degreeOf(roman);
    final tension = degree == null ? _neutralTension : (_tension[degree] ?? _neutralTension);
    return Color.lerp(_tonic, _dominant, tension)!;
  }
}
