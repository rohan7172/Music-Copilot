import 'package:flutter/material.dart';

/// A fixed, distinct color per key — an identity, not a theory lesson.
/// Unlike [HarmonicColor] (which colors a *chord* by its tension relative
/// to the key), this colors the *key itself*, so a piece in G major always
/// reads as the same hue, with no harmonic meaning attached.
class KeyColor {
  static const _pitchClasses = {
    'C': 0, 'C#': 1, 'Db': 1, //
    'D': 2, 'D#': 3, 'Eb': 3, //
    'E': 4, //
    'F': 5, 'F#': 6, 'Gb': 6, //
    'G': 7, 'G#': 8, 'Ab': 8, //
    'A': 9, 'A#': 10, 'Bb': 10, //
    'B': 11,
  };

  static final _fallback = HSLColor.fromAHSL(1, 260, 0.2, 0.75).toColor();

  /// A soft, paper-friendly color for [tonic] (e.g. "G", "F#", "Bb"),
  /// evenly spaced around the color wheel by pitch class so every key gets
  /// a visually distinct identity. Falls back to a neutral lavender-gray
  /// for an unrecognised tonic.
  static Color forTonic(String tonic) {
    final pitchClass = _pitchClasses[tonic];
    if (pitchClass == null) return _fallback;
    final hue = pitchClass * 30.0;
    return HSLColor.fromAHSL(1, hue, 0.45, 0.74).toColor();
  }
}
