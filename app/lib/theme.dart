import 'package:flutter/material.dart';

// impeccable:direction-contract
// THESIS: a companion-led, organic app — nothing on screen that doesn't
// trace back to a real sound event.
// OWN-WORLD: ivory ground, one lavender accent (Restrained strategy), soft
// rounded "pill" shapes with no hard outlines, flowing lines over bars/grids.
// FORM: brief-pinned — see Inpiration/FULL APP LOOK REFERENCE.png and
// docs/superpowers/specs/2026-10-29-visual-identity-overhaul.md.

/// The app's palette: warm ivory paper, graphite ink, one lavender accent.
/// Replaces the earlier "blank slate" navy accent as part of the visual
/// identity overhaul — everything else (paper, ink) was already close to
/// the new brief, so only the accent actually changes hue.
class Palette {
  static const paper = Color(0xFFFAF8F4);
  static const ink = Color(0xFF2B2B2B);
  static const accent = Color(0xFF8B7FC7);
  static const error = Color(0xFFB5523B);
}

/// Shared corner radius for the pill/organic shape language (buttons, chips,
/// cards) — one number so the whole app reads as one consistent shape
/// vocabulary rather than per-widget guesses.
class Shape {
  /// Fully round ("stadium") — for pill buttons and chips.
  static const pill = 999.0;

  /// Soft rounding for larger rectangular surfaces that aren't pills.
  static const soft = 20.0;
}

/// Primarily a mobile app, but built to also run as a desktop app — on a
/// wide window, content stays centered at a phone-like width instead of
/// stretching edge-to-edge (where the waveform and mascot would read as
/// thin and lost rather than organic).
class Layout {
  static const maxContentWidth = 480.0;
}

/// Fixed colors for the musical lines — three named hues, not derived from
/// the detected harmony. (A version of this app tried coloring the lines by
/// harmonic tension; reverted in favor of matching the reference board's
/// fixed purple/green/orange directly, which read simpler and clearer.)
class LineColors {
  static const purple = Palette.accent;
  static const green = Color(0xFF7FB88A);
  static const orange = Color(0xFFDB9B6C);
  static const all = [purple, green, orange];
}

/// The edge fluid field's two-hue gradient (see `widgets/fluid_field.dart`)
/// — a lighter lavender and a deeper purple, both already in the app's
/// existing accent family rather than a new hue.
class FluidColors {
  static const lavender = Color(0xFFB9ADEA);
  static const deepPurple = Color(0xFF5B4EA6);

  /// A very light lavender-white — concentrated near each bump's crest
  /// (see `widgets/fluid_field.dart`'s vertex-mesh highlight layer) for a
  /// sense of light catching the liquid's surface, rather than a flat fill.
  static const highlight = Color(0xFFEFE9FB);
}
