# Music Copilot — full UI overhaul from Stitch "Design System Foundation"

## Context

The user designed a complete new look in Google Stitch (project `17933563689007442256`, "Design System Foundation") and supplied an exact mascot reference (`Inpiration/Mascot States and Emotions Sheet.png`). The current Flutter UI (one 1,058-line `session_screen.dart` + a 1,128-line `score_canvas.dart` waveform/pitch-lane canvas, ivory/lavender theme, an older mascot with no grille) is replaced wholesale.

Decisions confirmed with the user:
- **UI only, real data.** Rebuild every screen in the Stitch visual language, but only surface what the app actually does (record/upload → Basic Pitch notes → chords + key → plain-language explanation → playback). Stitch controls with no backing feature (harmony voicings, mix balance, Vault/Settings tabs, Export MIDI, live cents/pitch, bpm, profile) are **omitted, not faked**.
- **Light theme**, as every rendered Stitch screen is (the design system's DESIGN.md text describes dark; the screens win).
- **Rebuild in place** in `app/` — keep platform scaffolding, permissions, audio/API/model layers.
- Header name stays **"Music Copilot"**.
- **Mascot: exactly the sheet** — capsule body, three grille strokes on top, two dot eyes, separate U-shaped stand arc beneath. Build every state that maps to a real event.

Brainstorm path: architectural. On approval, step 0 copies this plan to `docs/superpowers/specs/2026-10-30-stitch-ui-overhaul-design.md` and commits it.

## Visual system (from Stitch HTML tokens, light)

`app/lib/theme.dart` rewritten:
- **Palette:** frame `#726ABC` (lavender bezel around the canvas), canvas `#FBFBFE`, creamAlt `#F3F2F8` (chips/panels), container `#F0EBFF`, containerHigh `#EAE5FF`, primary `#5951A2` (filled buttons, playhead, active chip), noteActive `#7065C7`, noteSoft `#9D93E8`, fluid `#8E87D8`, fluidDeep `#6D64BD`, tint `#ECEBFA` (grid lines, scrub track), primaryFixed `#E4DFFF` (secondary CTA pill), ink `#3F3B63` (mascot stroke, labels), onSurface `#1B192F`, onSurfaceVariant `#474551`, outline `#787582`, error `#BA1A1A`. Mascot body/stand/eye colors sampled from the sheet PNG at build time.
- **Type:** Plus Jakarta Sans only (that's all Stitch HTML uses), bundled as TTF assets (400/500/600/700) under `app/assets/fonts/` — no runtime font fetching. Scale: headlineXl 40/48 w600 (mobile 30/38), headlineLg 28/36, headlineMd 22/28 w500, bodyLg 17/24, bodyMd 15/22, bodySm 13/18, labelLg 14/20 w600, labelMd 12/16 w500, labelSm 11/14 w600 +0.04em (uppercase section labels), musicNote 20/24 w700.
- **Shape/space:** radius 16 (panels), 24, 40 (canvas), full pills; space 4/8/16/24/40, margin 20.
- **Icons:** Flutter `Icons.*_rounded` equivalents of the Stitch Material Symbols (mic, upload_file, close, refresh, repeat, play/pause, arrow_forward).

## Architecture

```
lib/
  theme.dart                      REWRITE  tokens above
  session/session_controller.dart NEW      ChangeNotifier: all recording/analysis/playback state + actions
  widgets/app_frame.dart          NEW      lavender bezel, rounded cream canvas, header, fluid layer, max-width centering
  widgets/fluid_field.dart        KEEP     math unchanged; recolor to fluid/fluidDeep; reads level from controller
  widgets/mascot/mascot.dart      REWRITE  sheet-exact painter + per-mood animation
  widgets/mascot/mascot_mood.dart NEW      pure (phase, events) → MascotMood mapping (unit-tested)
  widgets/ui/{pill_button,round_action,chip,panel,section_label}.dart NEW  shared components
  widgets/contour/contour_panel.dart + contour_layout.dart NEW  note-pill pitch roll (replaces score_canvas)
  widgets/acoustic_stream.dart    NEW      live-level bar strip for recording
  screens/session_screen.dart     REWRITE  thin: AppFrame + AnimatedSwitcher over phase views
  screens/views/{idle,listening,analyzing,results}_view.dart NEW
  screens/splash_screen.dart      RESTYLE  keep chime + timing, new mascot/palette
  audio/, services/, models/, note_range.dart  KEEP as-is
  widgets/score_canvas.dart, key_color.dart, harmonic_color.dart  DELETE once nothing references them (Stitch is monochrome lavender; per-key hue wash goes away). Port `currentLevel` smoothing into the controller first.
```

**SessionController** is extracted (behavior-preserving) from `session_screen.dart` lines ~35–520: `AudioRecorder`, `AudioPlayer`, `ApiService`, phase, notes/chords/key/explanation, live amplitude history, auto-stop-on-silence, first-run hint (shared_preferences), playhead, loop flag, selection, error. Actions: `startRecording`, `stopAndAnalyze`, `cancelRecording`, `pickAndAnalyzeFile`, `togglePlay`, `seek`, `playNote(i)`, `playChord(i)`, `toggleLoop`, `newTake`. Views are stateless readers via `ListenableBuilder`. Reuse the existing `_playRange` / `_playFromHere` / `_trackPlayback` logic verbatim where possible.

## Screens (phase → Stitch reference)

1. **Idle** ← "Idle (2D Refined)" / "Mascot Companion & Fluid": large mascot centered with a couple of floating lavender dots; "Play something" (headlineLg) + "Sing, hum, or play anything" (bodyMd); two round actions with labels: **Live Mic** (primary filled) and **File Import** (creamAlt). Dropped: key/440 Hz pill, Pitch C4, Active Interval, Recent card, bottom tabs. First-run hint kept as the subtitle on first launch.
2. **Listening** ← "Live Listening": top row "● listening 00:16" pill (left) + round close/cancel (right); mascot in Listening state (sound arcs pulse with real level); acoustic-stream bar strip driven by real amplitude history with 00:00 / elapsed endpoints; full-width primary pill **"Stop & Analyze"**; hint line below. Dropped: detected pitch/cents/"in tune" (no live pitch detection). Fluid edges swell with level (existing behavior).
3. **Analyzing**: mascot Concentrating (narrowed eyes), "finding the notes…", stream bars ease flat, fluid settles to edges (existing).
4. **Results** ← "Note Analysis (2D Refined)":
   - Chip row: [↻ new take] [● key: C major] [N notes].
   - Mascot (smaller): Happy pop on arrival → Singing (eyes closed, notes floating) while playing → Idle. Descriptor line under it: what's sounding now during playback, else short key summary.
   - **"VOCAL CONTOUR" panel** (creamAlt, radius 16): pitch-lane grid labelled from the actual note range (`note_range.dart`), notes as pills on their lanes (active = noteActive filled with pitch label, others container), dashed glissando thread linking consecutive notes, playhead hairline with time tag, scrubber row `00:00 — ● — end`. Tap pill → play that note; tap/drag scrubber → seek.
   - **"CHORDS · tap to audition"** chip grid (name + roman numeral, active = primary) → plays that chord's span. Hidden when no chords.
   - Action row: loop toggle (round), play/pause (round primary 56), **"why it sounds this way →"** pill (primaryFixed) opening a bottom sheet with the explanation summary (chord mentions tappable, as today) and per-chord texts.
   - Zero notes → mascot Curious + "No notes found — try a clearer, sustained tone." + new take.
5. **Error** (network/backend/mic): mascot Surprised + message + retry pill.

Header everywhere: "Music Copilot" (labelLg, ink) + "upload" pill (creamAlt) = same action as File Import. Desktop/wide: frame centered at `Layout.maxContentWidth` (480), page background `frame` color.

## Mascot states (sheet → trigger)

| Sheet state | Trigger |
|---|---|
| 1 Idle (gentle float) | idle phase |
| 10 Sleepy (eyes closed, minimal motion) | idle with no interaction for ~30 s |
| 11 Tapping (quick reaction) | user taps mascot or any primary action |
| 5 Listening (side sound arcs pulse) | recording; arc opacity/spread from live level |
| 8 Concentrating (narrow eyes) | analyzing |
| 3 Happy (curved eyes, tick marks) / 7 Excited (bigger bounce) | results land; Excited if key confidence ≥ threshold |
| 6 Singing (eyes closed, notes drift) | results playback running |
| 4 Curious (tilt, "?") | zero notes / low-confidence key |
| 9 Surprised (wide eyes, tick marks) | error |

Skipped: 2 Looking Around, 12 per-note colors. Mapping lives in `mascot_mood.dart` as a pure function; painter draws body, grille (3 strokes; hidden in Sleepy/Concentrating per sheet), eyes (dot / arc-closed / arc-happy / narrowed-brow / wide), stand arc, and accessories (arcs, ticks, notes, "?"). Respect Reduce Motion (`MediaQuery.disableAnimations`) → static poses.

## Build order (one commit per step, `docs/concepts.md` updated in the same commit as any new concept)

0. Copy this plan to `docs/superpowers/specs/…-design.md`; commit.
1. Theme tokens + bundled Plus Jakarta Sans (download TTFs from Google Fonts — will confirm the download first) + `AppFrame` shell.
2. Extract `SessionController`; temporarily point the old screen at it; tests/analyze green.
3. Mascot rebuild + `mascot_mood_test.dart` (replaces `mascot_test.dart`); render all moods on a temporary debug gallery for a side-by-side check against the sheet, then remove the gallery.
4. Idle view. 5. Listening view + acoustic stream. 6. Analyzing + error. 7. Results view (contour panel + `contour_layout_test.dart`, chords, transport, explanation sheet).
8. Splash restyle. 9. Delete `score_canvas.dart`, `key_color.dart`, `harmonic_color.dart` and their tests if unreferenced; rewrite DESIGN.md from the built result (impeccable `document`), update PRODUCT.md brand/evidence sections (Stitch project + mascot sheet as references), update `docs/concepts.md`.

## Verification

- `cd app && flutter analyze && flutter test` after every step.
- `./dev.sh` (backend + Flutter web on :8080) → browser pane at 375×812 and ~800 wide: walk idle → File Import (use a clip from `backend/tests` fixtures if present, else a short recorded clip) → analyzing → results; tap note pills, chord chips, scrubber, loop, play/pause, explanation sheet; trigger error by stopping backend; leave idle 30 s for Sleepy. Screenshot each phase next to its Stitch counterpart (scratchpad PNGs) and the mascot gallery next to the sheet.
- One iOS Simulator pass for live mic recording + safe areas.
- Bounded QA: one batched inspection round, fix, at most one confirmation round.
