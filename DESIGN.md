# Design

<!-- impeccable:design-schema 1 -->

Recorded from the built result (2026-10-29), not from intention — see
`PRODUCT.md` for product context and
`docs/superpowers/specs/2026-10-29-visual-identity-overhaul.md` for the
brief this was built from.

## World

Brief-pinned, not generated: `Inpiration/FULL APP LOOK REFERENCE.png` plus
an explicit lavender/ivory ask. Restrained color strategy — one neutral
ground, one accent — carried through every surface.

## Palette (`app/lib/theme.dart`)

- `Palette.paper` `#FAF8F4` — ivory ground, every screen's background.
- `Palette.ink` `#2B2B2B` — body text, line art at low alpha.
- `Palette.accent` `#8B7FC7` — the one lavender accent: buttons, the
  record button, the mascot's body, the splash line.
- `Palette.error` `#B5523B` — unchanged from before this pass.
- `KeyColor` (`app/lib/key_color.dart`) is a **separate, intentional**
  system layered on top once a key is detected: each of the 12 keys gets
  its own hue (`pitchClass * 30°`), used for the ambient wash, the
  waveform's "arrival" color, and the key-name text. This is not a
  palette violation — it's the harmonic-identity layer the rest of the
  design explicitly makes room for (see "Ambient atmosphere" in
  `docs/concepts.md`).

## Shape (`app/lib/theme.dart`)

- `Shape.pill` (999, i.e. fully round) — every button/chip
  (`_QuietButton`, chord tabs) is a stadium shape: `RRect` with a corner
  radius of half the shorter side.
- No hard outlines anywhere; surfaces are separated by soft shadows
  (small blur + offset) or color alone, never a 1px border.

## Components

- **Mascot** (`app/lib/widgets/mascot.dart`) — a capsule body (the
  stadium trick above), two dot eyes, one curved mouth line. Four
  expressions driven by `Phase` (`expressionForPhase`, pure + unit
  tested): idle (slow breath + periodic blink), listening (whiskers that
  pulse with live input level), analyzing (gentle head-tilt), revealing
  (a brief `easeOutBack` pop + deeper smile when results land). Large and
  centered at rest; shrinks to a small presence pinned to the top of the
  screen the moment there's a task underway, clear of the waveform and
  pitch-lane area below it.
- **`_QuietButton`** — the one secondary-button shape across the app:
  an ivory stadium pill with a soft shadow and `InkWell` ripple.
- **Splash** (`app/lib/screens/splash_screen.dart`) — one flowing line
  on ivory, three Gaussian "ripples" timed to a synthesized three-note
  chime (`scripts/generate_splash_chime.py`), then a plain fade into the
  session screen. Tap anywhere to skip.
- **Waveform / pitch lanes / chords** (`app/lib/widgets/score_canvas.dart`)
  — unchanged in structure by this pass; inherits the new accent color
  automatically since it already referenced `Palette.accent`.

## Layout

- `Layout.maxContentWidth` (480) — every screen centers its content in a
  phone-proportioned column and lets the ivory ground show on either
  side past that width, so the app reads correctly both as the mobile
  app it primarily is and as a desktop window. Verified at 375px
  (mobile) and an 800px (desktop-width) viewport.

## What this pass did not touch

- Any new screen or route (Home / Library / Explore-Theory / Settings
  from the reference board) — deferred; see the spec doc.
- Exact color tuning beyond the stated lavender/ivory values.
- The mascot is not yet named.
