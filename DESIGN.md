# Design

<!-- impeccable:design-schema 1 -->

Recorded from the built result (2026-10-30), not from intention. Brief:
Google Stitch project "Design System Foundation" (`17933563689007442256`,
light screens) and `Inpiration/Mascot States and Emotions Sheet.png`.
Spec: `docs/superpowers/specs/2026-10-30-stitch-ui-overhaul-design.md`.

## World

Brief-pinned. A lavender bezel (`#726ABC`) around one rounded near-white
canvas; quiet lavender-tinted chips and panels on it; one deep violet for
the thing you can press next; lavender fluid walls along the canvas edges
that move with the sound. Light only: every rendered Stitch screen is
light, so the dark palette in the Stitch DESIGN.md text was not used.

## Palette (`app/lib/theme.dart`, from the Stitch Tailwind config)

- `frame #726ABC` bezel · `canvas #FBFBFE` ground
- `creamAlt #F3F2F8` chips, quiet buttons, panels · `container #F0EBFF`,
  `containerHigh #EAE5FF`, `containerHighest #E4DFFE` note pills
- `primary #5951A2` filled buttons, playhead, active chip
- `primaryFixed #E4DFFF` / `onPrimaryFixed #17065E` secondary CTA pill
- `noteActive #7065C7` sounding note · `noteSoft #9D93E8` tints
- `fluid #8E87D8` → `fluidDeep #6D64BD` edge fluid gradient
- `tint #ECEBFA` grid rules and scrub track
- Text: `ink #3F3B63` labels, `onSurface #1B192F` headings,
  `onSurfaceVariant #474551` body, `outline #787582` secondary
- `error #BA1A1A`
- Mascot (sampled from the sheet): body/stand `#9688D4`, grille
  `#7164B5`, eyes `#3F3578`, accessories `#9D90DA`

The per-key hue system (`KeyColor`, `HarmonicColor`) was removed: Stitch is
monochrome lavender, and key identity now lives in text.

## Type

Plus Jakarta Sans only, bundled (`app/assets/fonts/`, weights 400–700).
Scale: headlineXl 40/48, headlineLg 28/36 w600 (screen titles),
headlineMd 22/28 w500, bodyLg 17/24, bodyMd 15/22, bodySm 13/18, labelLg
14/20 w600, labelMd 12/16 w500 (chips), labelSm 11/14 w600 +0.06em
uppercase (section labels), musicNote 20/24 w700. Times and counts use
tabular figures.

## Shape, space, depth

- Radii: panel 16, large 24 (sheets), canvas 40, pills fully round.
- Space: 4 / 8 / 16 / 24 / 40; page margin 24 inside the canvas.
- No outlines. Only filled primary controls cast a shadow (violet at 20%,
  blur 14, y 4); everything else separates by tone.

## Components (`app/lib/widgets/`)

- **AppFrame / AppHeader** — bezel, canvas, "Music Copilot" + an `upload`
  pill (hidden while recording/analyzing). Content centers at 480 max
  width on wide windows.
- **Pressable** — shared press feedback (scale 0.95), pointer cursor,
  keyboard activation, semantics. Under **PillButton** (primary / soft /
  quiet), **RoundAction** (circle, optional caption, toggle state),
  **InfoChip** (status dot or icon + mixed-weight text), **SectionLabel**.
- **Mascot** (`mascot/`) — drawn to the sheet's proportions in a 220×200
  design box: capsule body, three-stroke grille, dot eyes, cradle stand.
  Moods come from a pure `moodFor()`: idle, sleepy (30 s untouched),
  tapped, listening (sound arcs follow mic level), concentrating
  (analyzing), happy / excited (results land; excited when key confidence
  ≥ 0.75), singing (playback), curious (nothing found / unsure key),
  surprised (error). Mood changes swap eyes behind a blink. Reduce
  Motion holds resting poses.
- **Edge fluid** (`fluid_field.dart`) — metaball-style walls under the
  header; reach is 16% of the shorter side, easing to half once results
  are on screen; pulses with live volume while recording and per note
  during playback.
- **AcousticStream** — live loudness bars (3 × 40 ms samples per bar),
  newest right, ending in a "now" dot; flattens while analyzing.
- **ContourPanel** — "VOCAL CONTOUR": notes as pills on fitted pitch
  lanes, dashed melody thread, playhead with time tag, scrubber. Pills
  carry their name when every note has room; otherwise only the sounding
  note is labelled. Tap a pill to hear it; tap elsewhere to play from there.
- **Chord chips** — horizontal row, name + roman numeral, active filled.

## Screens (`app/lib/screens/`)

Splash (mascot sleeps → sings to the chime → wakes) → one session screen
that cross-fades between Idle (Play something · Live mic · File import),
Listening/Analyzing (shared view; status chip + discard, mascot, stream,
Stop & analyze), Results (new take · key · note count, mascot + key
confidence line, contour, chords, loop / play / "why it works" sheet),
No-notes, and Error (title, recovery message, Record again / Back to
start).

## Deliberately not built

Stitch controls with no backing feature: harmony voicings, mix balance,
Play Harmony, Songs & Vault, Settings & Tuner, Export MIDI, live cents /
pitch readout, bpm, profile, bottom tab bar. Mascot states "looking
around" and per-note colors.
