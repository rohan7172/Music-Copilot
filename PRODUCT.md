# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Currently just the developer (rohan7172) — a web developer learning
mobile app development for the first time, using this project to learn
Flutter/Dart, app deployment, and the ML/music-theory concepts behind
the app, not just to ship a product. Design can assume a single
sophisticated, patient user for now; no broader onboarding audience
yet.

## Product Purpose

Record or upload a piece of music, recognize its notes via ML (Basic
Pitch), convert them to chords, detect the key, and explain the
underlying music theory in plain language — so the user understands
*why* a piece sounds the way it does, not just what notes it contains.

## Positioning

Most pitch-detection apps surface raw note/frequency data as a static
chart or a scrolling piano roll. Music Copilot's mechanism is
different: detection renders as a living, ambient visualization that's
colored and animated by the music's actual key and harmony, narrated by
a mascot companion, and explained in plain language rather than left
for the user to interpret from raw theory labels.

## Operating Context

- Recording happens live via the device microphone, or by importing an
  existing audio file.
- Analysis is a request/response round-trip to a local FastAPI backend
  (`http://127.0.0.1:8000` in dev) — not on-device, not real-time
  streaming analysis.
- Primary dev/test loop today is Flutter web via `./dev.sh`
  (`localhost:8080`) plus browser-pane automation; the iOS Simulator is
  also available for native verification in this environment. Android
  has not yet been manually verified.
- `docs/concepts.md` is a living index the user relies on to learn the
  concepts behind the code — it must stay current with new concepts
  introduced, in the same commit as the code that introduces them.

## Capabilities and Constraints

- Ships one shared custom visual identity to iOS and Android rather
  than adapting per-OS (Cupertino vs. Material) — confirmed by explicit
  user choice during this redesign's init round. Each platform's
  *mechanical* OS guarantees (safe-area insets, back gesture/button,
  touch-target minimums, Dark Mode/Reduce Motion system settings) still
  apply even where the visual language itself departs from native
  idiom; "adaptive" above records the two-native-platform target, not
  genuine per-OS design adaptation.
- Primarily a mobile app, but also intended to run as a desktop app
  (macOS/Windows/Linux scaffolding already exists from `flutter
  create`; not yet built/packaged for distribution, just not ruled
  out). Screens must therefore respond to window size, not assume a
  phone viewport: content centers at a phone-proportioned max width
  (`Layout.maxContentWidth` in `app/lib/theme.dart`) on a wide window
  rather than stretching edge-to-edge.
- Current implementation: live recording + file upload, Basic Pitch
  note recognition, rule-based chord/key detection (major/minor only —
  no modal detection yet), rule-based plain-language explanations. The
  UI is one session screen (`app/lib/screens/session_screen.dart`)
  cross-fading between per-phase views (`app/lib/screens/views/`), all
  reading one `SessionController` (`app/lib/session/`).
- No persistence between sessions yet; no user accounts.
- The UI was rebuilt on 2026-10-30 from the Google Stitch project
  "Design System Foundation"; see
  `docs/superpowers/specs/2026-10-30-stitch-ui-overhaul-design.md`. It is
  UI-only: Stitch controls with no backing feature (harmony voicings, mix,
  library/Vault, settings/tuner, MIDI export) are omitted, not faked.

## Brand Commitments

- Product name: "Music Copilot" (confirmed, from the README and
  project name).
- The mascot — a capsule-bodied microphone with a three-line grille, two
  dot eyes and a cradle-shaped stand — is the app's recurring visual
  identity, drawn exactly as `Inpiration/Mascot States and Emotions
  Sheet.png` shows it, including that sheet's emotional states. Not yet
  named; naming is an open, optional follow-up.
- Palette: light lavender — a lavender bezel around a near-white canvas,
  deep violet for primary actions — taken from the Stitch project's light
  screens (see `DESIGN.md`). Typeface: Plus Jakarta Sans.

## Evidence on Hand

- Google Stitch project "Design System Foundation"
  (`17933563689007442256`) — the binding visual reference since
  2026-10-30: Idle, Live Listening, Note Analysis and Harmony Studio
  screens (plus fluid and "2D refined" variants), and its design-system
  tokens. Its light screens win over its DESIGN.md text, which describes
  a dark theme.
- `Inpiration/Mascot States and Emotions Sheet.png` — the exact mascot and
  its 12 states.
- `Inpiration/FULL APP LOOK REFERENCE.png` — the earlier visual-world
  reference, superseded by Stitch: 8 mobile screens (Home, Listening, Detected Note, Harmony
  Suggestions, Harmony Playing, Library, Explore/Theory, Settings) in
  lavender-on-ivory with the pill mascot, soft color-coded flowing
  lines, pill-shaped suggestion chips, a 3-icon bottom tab bar.
- `Inpiration/MASCOT_SUGGESTION1.png` — an earlier mascot icon treatment,
  superseded by the states sheet.
- `Inpiration/Audio Presence Concepts.rtf`,
  `Inpiration/Organic UI Principles.rtf`,
  `Inpiration/First-Use Experience Onboarding.rtf`,
  `Inpiration/MASCOT_FEATURE.textClipping` — written direction on
  mascot behavior/personality, a companion-led discovery-first
  onboarding flow, "organic" shape/motion/relationship principles, and
  screen-by-screen UX philosophy (one job per screen, sound is the
  hero, reveal depth progressively).
- `Inpiration/27edb01f....jpg`, `Inpiration/c6e174f....jpg` — secondary
  mood-board images showing alternate mic-button/recording-list
  treatments in different color schemes; lower-priority structural
  references, not the committed palette.
- No existing user testimonials, usage data, or press.

## Product Principles

1. The sound is the hero — visualization and layout foreground what
   was actually heard, not UI chrome or the mascot.
2. Reveal depth progressively — don't permanently surface every
   note/chord/confidence score/theory label at once; let the user open
   detail when curious.
3. The mascot's behavior is functional, not decorative — its state
   always traces back to a real audio/analysis event (listening,
   detecting, uncertain, revealing), never a generic idle loop.
4. This is a personal learning project first — prefer choices the user
   can understand and reason about over opaque ones, consistent with
   the rest of the codebase (e.g. rule-based harmony analysis over a
   black-box model).

## Accessibility & Inclusion

No product-specific requirement established yet (single-user personal
project for now).
