import 'package:flutter/material.dart';

// impeccable:direction-contract
// THESIS: a companion-led, organic app — nothing on screen that doesn't
// trace back to a real sound event.
// OWN-WORLD: a lavender bezel around one rounded near-white canvas; quiet
// lavender-tinted chips and panels; one deep violet for the thing you can
// press right now; fluid lavender walls that move with the sound.
// FORM: brief-pinned — Google Stitch project "Design System Foundation"
// (17933563689007442256), light screens, and the mascot sheet at
// Inpiration/Mascot States and Emotions Sheet.png.

/// Color tokens, taken directly from the Stitch screens' Tailwind config
/// (light theme) so the app and the designs stay one system.
class Palette {
  /// The lavender bezel the whole app sits inside.
  static const frame = Color(0xFF726ABC);

  /// The rounded near-white canvas everything is drawn on.
  static const canvas = Color(0xFFFBFBFE);

  /// Chips, quiet buttons and panels: a hair darker than the canvas.
  static const creamAlt = Color(0xFFF3F2F8);
  static const container = Color(0xFFF0EBFF);
  static const containerHigh = Color(0xFFEAE5FF);

  /// The one "press me" color: filled buttons, playhead, active chip.
  static const primary = Color(0xFF5951A2);
  static const onPrimary = Color(0xFFFFFFFF);

  /// The secondary call-to-action pill and its text.
  static const primaryFixed = Color(0xFFE4DFFF);
  static const onPrimaryFixed = Color(0xFF17065E);

  /// A note that is sounding / selected, and the softer harmony tint.
  static const noteActive = Color(0xFF7065C7);
  static const noteSoft = Color(0xFF9D93E8);

  /// The edge fluid's two hues.
  static const fluid = Color(0xFF8E87D8);
  static const fluidDeep = Color(0xFF6D64BD);

  /// Hairlines: pitch-grid rules, the scrub track.
  static const tint = Color(0xFFECEBFA);

  /// Text: labels and the mascot's ink, body text, secondary text.
  static const ink = Color(0xFF3F3B63);
  static const onSurface = Color(0xFF1B192F);
  static const onSurfaceVariant = Color(0xFF474551);
  static const outline = Color(0xFF787582);
  static const outlineVariant = Color(0xFFC8C4D2);

  static const error = Color(0xFFBA1A1A);
}

/// The mascot's own colors, sampled from the reference sheet so it reads as
/// exactly that character rather than a re-tint of the UI palette.
class MascotColors {
  static const body = Color(0xFF9688D4);
  static const grille = Color(0xFF7164B5);
  static const eye = Color(0xFF3F3578);
  static const accent = Color(0xFF9D90DA);
}

/// The one typeface the Stitch designs use, bundled under assets/fonts.
const _family = 'PlusJakartaSans';

/// Type scale from the Stitch config. Letter spacing there is in em; Flutter
/// wants logical pixels, so each one is multiplied out by its font size.
class TextStyles {
  static const headlineXl = TextStyle(
    fontFamily: _family,
    fontSize: 40,
    height: 48 / 40,
    letterSpacing: -0.8,
    fontWeight: FontWeight.w600,
    color: Palette.onSurface,
  );
  static const headlineXlMobile = TextStyle(
    fontFamily: _family,
    fontSize: 30,
    height: 38 / 30,
    letterSpacing: -0.45,
    fontWeight: FontWeight.w600,
    color: Palette.onSurface,
  );
  static const headlineLg = TextStyle(
    fontFamily: _family,
    fontSize: 28,
    height: 36 / 28,
    letterSpacing: -0.28,
    fontWeight: FontWeight.w600,
    color: Palette.onSurface,
  );
  static const headlineMd = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w500,
    color: Palette.onSurface,
  );
  static const bodyLg = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w400,
    color: Palette.onSurface,
  );
  static const bodyMd = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: Palette.onSurfaceVariant,
  );
  static const bodySm = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    color: Palette.onSurfaceVariant,
  );
  static const labelLg = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.14,
    fontWeight: FontWeight.w600,
    color: Palette.ink,
  );
  static const labelMd = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.24,
    fontWeight: FontWeight.w500,
    color: Palette.ink,
  );

  /// Small uppercase section labels ("VOCAL CONTOUR") — callers uppercase
  /// the string; the generous tracking is what makes it read as a label.
  static const labelSm = TextStyle(
    fontFamily: _family,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.66,
    fontWeight: FontWeight.w600,
    color: Palette.onSurfaceVariant,
  );
  static const musicNote = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    height: 24 / 20,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w700,
    color: Palette.ink,
  );

  /// Times and counts: the same face with tabular figures so a running
  /// clock doesn't jitter sideways as its digits change.
  static const tabular = [FontFeature.tabularFigures()];
}

/// Corner radii: panels, larger surfaces, the canvas itself, and pills.
class Shape {
  static const panel = 16.0;
  static const large = 24.0;
  static const canvas = 40.0;
  static const pill = 999.0;
}

/// Spacing steps from the Stitch config.
class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;

  /// Horizontal page margin inside the canvas.
  static const margin = 20.0;
}

/// Primarily a mobile app, but built to also run as a desktop app — on a
/// wide window the framed canvas stays centered at a phone-like width
/// instead of stretching edge-to-edge.
class Layout {
  static const maxContentWidth = 480.0;

  /// How much lavender bezel shows around the canvas.
  static const bezel = 8.0;
}

/// Motion timings shared across views, so the app moves with one rhythm.
class Motion {
  static const quick = Duration(milliseconds: 180);
  static const settle = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.primary,
    primary: Palette.primary,
    onPrimary: Palette.onPrimary,
    surface: Palette.canvas,
    onSurface: Palette.onSurface,
    error: Palette.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _family,
    scaffoldBackgroundColor: Palette.frame,
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.primary,
      selectionColor: Palette.noteSoft.withValues(alpha: 0.35),
      selectionHandleColor: Palette.primary,
    ),
    focusColor: Palette.noteSoft.withValues(alpha: 0.3),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.canvas,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Palette.outlineVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.large)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.onSurface,
      contentTextStyle: TextStyles.bodySm.copyWith(color: Palette.canvas),
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
    ),
  );
}
