# Visual Identity Overhaul — mascot, splash, lavender/ivory theme

Date: 2026-10-29
Status: approved, in implementation

## Why

The app functions (record/upload → Basic Pitch note detection →
rule-based chord/key/theory explanation → one animated canvas screen)
but has no visual identity: a "blank slate" warm-paper-and-navy theme,
no mascot, no splash screen, no organic shape language. The user
assembled reference material (`Inpiration/`) — an 8-screen concept
board, a mascot character, and written direction on mascot behavior,
"organic" UI principles, and onboarding — and wants the app to "start
feeling like the app it's meant to be." New *functionality* implied by
those references (ear training, a theory explorer, a recordings
library, settings) is explicitly out of scope; this is a visual-only
pass applied to what already exists.

## Direction (pinned by the user's references, not generated)

- **Thesis:** a companion-led, organic app — a recurring mascot and
  audio-reactive visuals replace generic dashboard chrome; nothing on
  screen that doesn't trace back to a real sound event.
- **World:** ivory/cream ground (close to the existing `Palette.paper`,
  kept), lavender as the single accent (replacing the existing navy
  `Palette.accent`), soft rounded shapes with no hard outlines, flowing
  color-coded lines rather than bars/grids (the canvas already does
  this), pill-shaped buttons.
- **Mascot:** a rounded "pill" character — two dot eyes, one curved
  mouth/grille line, nothing else (`Inpiration/MASCOT_SUGGESTION1.png`).
  A supporting character: centered and calm when idle, small/out of the
  way once the user is actively recording. State (idle / listening /
  analyzing / revealing) always traces to the app's real `Phase`.
- **Splash:** ivory screen, one flowing line, a pulse that plays 2-3
  notes as the line flexes, then settles into the main screen.
- **Color strategy:** Restrained — one neutral ground, one accent. This
  is the default for an "Operate" surface (task completion, not
  persuasion) and matches exactly what the user asked for.

This direction was not selected from generated alternatives — the user
supplied a concrete, pinned visual world via the reference board and an
explicit palette ask, which (per the design process used) overrides
generating or evaluating other candidate directions.

## Scope

In scope: theme colors/shape tokens, a reusable mascot widget, a splash
screen with a sound cue, and reskinning the existing single session
screen's chrome around these. Out of scope: any new screen, route, or
feature (Home/Library/Explore/Settings, ear training, etc.) — those are
new information architecture, not visual polish, and are explicitly
deferred by the user.

## Architecture

- `app/lib/theme.dart` — `Palette` gains the lavender accent and a
  shared corner-radius constant. `KeyColor` (per-musical-key hue
  system) is untouched; it's orthogonal (harmonic identity, not app
  chrome).
- `app/lib/widgets/mascot.dart` (new) — `CustomPainter` capsule
  character with an idle/listening/analyzing/revealing state model,
  animated via the same clock-driven timestamp pattern already used in
  `score_canvas.dart` (no new animation machinery introduced).
- `app/lib/screens/splash_screen.dart` (new) — shown first from
  `main.dart`; reuses the canvas's line-drawing technique; plays a
  synthesized short tone-arpeggio asset via `just_audio` (already a
  dependency); navigates to `SessionScreen` on completion or tap.
- `app/lib/screens/session_screen.dart` — restyle `_QuietButton`/
  `_RecordButton` and the status-text line to the new language;
  integrate the mascot where the status text currently stands alone.
  No change to recording/upload/analysis/playback logic.

## Testing

- `flutter analyze` / `flutter test` stay clean throughout.
- Mascot state transitions are pure enough to unit test
  (phase → mascot state mapping); painting logic itself follows this
  codebase's existing precedent of no tests for pure `CustomPainter`
  drawing code.
- Manual visual verification on both native (iOS Simulator) and
  Flutter-web (browser pane), screenshotting idle, listening, and
  settled states plus the splash.
