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

  static final _fallback = HSLColor.fromAHSL(1, 260, 0.45, 0.72).toColor();
  static final _fallbackVivid = HSLColor.fromAHSL(1, 260, 0.6, 0.55).toColor();
  static final _fallbackDark = HSLColor.fromAHSL(1, 260, 0.4, 0.32).toColor();

  static double? _hueFor(String tonic) {
    final pitchClass = _pitchClasses[tonic];
    return pitchClass == null ? null : pitchClass * 30.0;
  }

  /// A paper-friendly but genuinely saturated color for [tonic] (e.g. "G",
  /// "F#", "Bb"), evenly spaced around the color wheel by pitch class so
  /// every key gets a visually distinct identity. Falls back to a neutral
  /// lavender-gray for an unrecognised tonic.
  static Color forTonic(String tonic) {
    final hue = _hueFor(tonic);
    if (hue == null) return _fallback;
    return HSLColor.fromAHSL(1, hue, 0.70, 0.70).toColor();
  }

  /// The same hue and key identity as [forTonic], but bolder — for a
  /// foreground element (like the waveform) that should read as fully
  /// contrasting against the softer ambient wash behind it.
  static Color forTonicVivid(String tonic) {
    final hue = _hueFor(tonic);
    if (hue == null) return _fallbackVivid;
    return HSLColor.fromAHSL(1, hue, 0.82, 0.52).toColor();
  }

  /// The same hue as [forTonic], darkened for legible text on paper rather
  /// than plain ink once the key's color has arrived.
  static Color forTonicDark(String tonic) {
    final hue = _hueFor(tonic);
    if (hue == null) return _fallbackDark;
    return HSLColor.fromAHSL(1, hue, 0.55, 0.30).toColor();
  }
}
