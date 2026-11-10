# Music engine plan: suggested progressions for melodies, real recognition for songs

## Context

Today `/analyze` runs Basic Pitch and then `backend/app/harmony.py` looks up which chord the simultaneous notes spell. That's the wrong model for this app's purpose. For a hummed melody there are no chords to find, so the job is **suggesting** progressions that fit the melody. For an uploaded song, the note lookup fails on real audio (design doc, "Why chord detection is failing"). It also floods the screen with every transcribed note, with no sense of which instrument played what.

Goal: when you record a melody, the app offers three progressions:
- **Safe**: what theory picks.
- **Colourful**: a richer option.
- **Bold**: an exciting option an LLM proposes and the engine validates.

Each comes with reasons and can be played under your recording. When you upload a song, the app recognises the progression the song actually uses, suggests alternatives for its melody, and shows the parts (melody, bass, harmony) separately with their roles explained.

Decisions so far:
- Gemini proposes the Bold option and the theory engine checks it.
- Gemini is on its free tier.
- PyTorch models run on the song path only.
- Timing is an optional click or count-in; otherwise the grid is estimated and you can nudge it.

The work splits into **three parts, built in order**. Each one ships on its own. Part 1 is planned to implementation level; Parts 2 and 3 are planned at design level and get their own detailed plan when we reach them.

---

## Part 1: the melody harmoniser (build first)

Everything here is backend Python plus the results UI. It needs no new heavy ML.

### 1a. Melody preparation (`backend/app/melody.py`, new)
- **Route the input.** A polyphony score (average overlapping confident notes, from Basic Pitch's output) labels each take `melody`, `polyphonic` or `full_mix`. Melody takes go to the harmoniser; `full_mix` goes to Part 2 once that exists. Until then, a full mix is treated as melody using its top line, with a note saying so in the UI.
- **Pick out one melody line.** Take the highest confident note at each moment, merge repeated notes, and drop very short blips. Reuse `without_overtones` from `harmony.py`.

### 1b. Beat grid (`backend/app/timing.py`, new)
- **If a click was used:** the app sends its tempo and count-in offset, and the grid is exact.
- **Otherwise:** estimate it.
  - Tempo comes from librosa's onset-strength tempogram, limited to 60–160 BPM.
  - The downbeat is the phase that puts the most long and loud notes on beat 1.
  - Default meter is 4/4, with 3/4 as an option.
  - The grid is marked `guessed: true`.
- **Beat strength** is weighted: beat 1 > beat 3 > beats 2 and 4 > off-beats.

### 1c. Key (in `melody.py`)
- Krumhansl-Schmuckler on the melody, weighting each note by duration × beat strength.
- Return the key plus a runner-up (often the relative key).
- Reuse `_describe_key` from `harmony.py`.

### 1d. Harmoniser engine (`backend/app/harmoniser/`, new package)
This follows the design doc's scoring formula, S = Σ[M + K] + Σ[P + R] + C:
- **`vocab.py`: candidate chords per key.** Diatonic triads and sevenths, secondary dominants (V/V, V/vi), borrowed chords (♭VI, ♭VII, iv in major) and sus chords. Each is tagged diatonic, colour or chromatic. Roman numerals come from music21; reuse `_roman` in `harmony.py`.
- **`scoring.py`: how well a chord fits a bar, and the moves between bars.**
  - **Melody fit (M):** each note is weighted by duration × beat strength.
    - Chord tones get full credit.
    - Tensions (9th, 13th, or 11th over minor) get partial credit and are labelled "colour".
    - A weak-beat passing or neighbour note that moves by step is neutral.
    - A strong or long clash gets a penalty.
  - **Key cost (K):** diatonic chords are free; colour and chromatic chords cost progressively more.
  - **Root motion (R):** a bonus for moving down a fifth or by step.
  - **Cadence (C):** a bonus for V→I or IV→I at phrase ends, and a penalty for staying on one chord too long. Phrase ends are long notes, rests, and bars 4 and 8.
- **`prior.py`: P(next chord | previous, mode).** A trigram table with backoff, loaded from `backend/app/data/progression_prior.json`.
- **`search.py`: build whole progressions.** Slots are one chord per bar by default, with a half-bar option. A beam search (width ~50) keeps the N best whole progressions, and three diverse ones are picked from them (they must differ in at least a third of the bars):
  - **Safe:** the best score under a high cost on non-diatonic chords.
  - **Colourful:** must include a seventh, borrowed chord or secondary dominant.
  - **Surprising:** a chord the corpus rarely uses here but the melody fits well. This is the fallback for Bold when the LLM isn't available.
- **`reasons.py`: why each chord fits.** The two largest score terms per chord become sentences from templates. They follow the doc's worked example: "Your long E becomes a dreamy 7th over F." The function wording comes from `explain.py`'s blurbs.

### 1e. Corpus prior (`scripts/build_progression_prior.py`, new; run once)
- **Source:** download Chordonomicon (Hugging Face, ~264 MB CSV).
- **Convert:** turn each song's chords into Roman numerals relative to its estimated key (Krumhansl over its chord tones), collapse to the engine's vocabulary, and count bigrams and trigrams per mode, plus per `main_genre` for later style presets.
- **Output:** a compact JSON file (a few MB) that is committed. The raw dataset is not committed.
- **Licence:** Chordonomicon is **CC BY-NC 4.0**, which is fine for this personal project but has to be replaced before any commercial use. Noted in PRODUCT.md.

### 1f. Bold option with Gemini (`backend/app/llm.py`, new)
1. **Ask Gemini for options.** Gemini gets a compact, factual summary: the key, the per-bar melody notes with their beat weights, the phrase ends, and the Safe and Colourful choices. It's asked for 3 adventurous progressions in Roman numerals, returned as JSON.
2. **The engine validates them.** Each one is parsed into the vocabulary (chords it can't parse are rejected), scored with M and K per bar, and rejected if any strong-beat clash goes over the threshold. The best surviving one becomes **Bold**, with `source: "llm"`.
3. **Gemini writes the explanation from engine facts.** A second Gemini call gets the engine's facts for the Bold progression: which melody notes are chord tones or colour, each chord's function, and how rare it is in the corpus. It writes a short "why this is exciting" in the companion's voice. It's told to use only those facts.
4. **Fallback:** with no `GEMINI_API_KEY`, a timeout (~6 s) or invalid output, Bold becomes the corpus Surprising option with template reasons. Analysis never fails because of the LLM.
- **Config:** the key and model name come from the environment (`.env`, gitignored). Only the symbolic summary is sent to Google, never audio. Responses are cached per melody hash.

### 1g. Backing audio (`backend/app/synth.py`, new)
- Render each progression as a soft pad: a three-voice voicing near middle C, a bass root, and a fade at each chord change.
- Rendering uses numpy additive synthesis, the same technique as `scripts/generate_splash_chime.py`, to a WAV aligned to the beat grid.
- New endpoint: `POST /backing` takes `{progression, grid, duration}` and returns WAV bytes.

### 1h. API (`backend/app/main.py`)
- **`/analyze` returns:** `route`, `melody[]`, `grid {bpm, downbeat, beats[], meter, guessed}`, `key {…, runner_up}`, `progressions[] {kind: safe|colourful|bold, source, character, chords[] {bar, start, end, symbol, roman, function, fit, reasons[]}}`, `insight`, plus the existing `notes`.
- **The old `chords` and `explanation` fields are removed** for melody takes.
- **New `POST /harmonise`:** takes `{melody, grid, key?}` and re-runs only the harmoniser, without re-transcribing. It powers instant re-suggestion after you nudge the downbeat or tempo, or override the key.

### 1i. App
- **Model:** `app/lib/models/harmony.dart` gains `Progression`, `ProgressionChord` and `BeatGrid`, plus parsing tests.
- **Recording:** the listening view gets an optional click and count-in toggle with a tempo picker. The click is a short asset played on a timer, and the tempo and offset are sent along with the take.
- **Contour panel:** bar lines from the grid, plus a chord-pill ribbon aligned to bars above the roll. `contour_layout.dart` gains bar and pill geometry, with tests.
- **Results view:** three swipeable progression cards (Safe, Colourful, Bold) with chord pills and a one-line character.
  - Swiping a card fetches `/backing` and loops it under the recording; `SessionController` gets a second, synced `AudioPlayer`.
  - Tapping a pill opens its "why" sheet.
  - A "guessed grid" chip offers downbeat ← / → and tempo ± controls, which call `/harmonise`.
  - The previous "chords" row and summary sheet are replaced.
- **Mascot:** curious on the Bold card, happy when a cadence resolves during playback.
- **Docs:** `docs/concepts.md` gets entries for beat grids, the scoring terms, beam search, corpus priors, LLM-proposes-engine-validates, and synthesis. They land in the same commits as the code.

### Part 1 tests
- Unit tests per module, in pytest style like `backend/tests/test_harmony.py`.
- **Golden melodies:** public-domain tunes hand-coded as notes, each with a known harmonisation the Safe option must mostly match:
  - Twinkle Twinkle → C C F C | F C G C
  - Ode to Joy
  - Happy Birthday
  - Frère Jacques
- **Gemini:** tested with a stubbed client. Cases: a valid proposal, a clashing proposal (rejected), garbage output (falls back), and a timeout.
- **App:** parsing and layout tests.

---

## Part 2: songs, i.e. recognise the real progression (design level)

- **Install:** PyTorch, `demucs`, `beat_this` and the BTC chord model, through an optional `requirements-songs.txt`. Models load lazily on the first song upload, so melody takes stay fast. They run on Apple's GPU (MPS) where it's available.
- **Pipeline for `route == full_mix`:**
  1. HTDemucs splits the song into 4 stems.
  2. Beat This! finds beats and downbeats on the full mix.
  3. BTC estimates the chords, on the mix or on the "other" stem plus the bass stem.
  4. Basic Pitch on the bass stem gives the bass note per beat.
  5. A beat-synchronous Viterbi decodes the chords: emissions are BTC probabilities plus agreement with the bass, and transitions come from the Part 1 corpus prior. It adapts `_viterbi` from `harmony.py`.
  6. The key comes from the decoded chords.
- **Long analysis:** a job id plus `GET /jobs/{id}` polling, with progressive results (beats and chords first, stems later). Clips are capped at about 90 s by default.
- **Output:** an "Original" progression card shown alongside Safe, Colourful and Bold. The Part 1 harmoniser runs on the vocal stem's melody with the recognised grid, so the alternatives fit the song's real tune.
- **Retiring the old code:** the note-lookup in `harmony.py` is removed from the song path.

## Part 3: show the parts of a song, not a wall of notes (design level)

- **Per-stem transcription:**
  - Vocals → one melody line (the 1a extraction).
  - Bass → bass line.
  - "Other" → summarised as the recognised chords plus a playing style (strummed, arpeggiated or sustained, from onset patterns), not as raw notes.
  - Drums → tempo and groove only.
- **Role explanations from templates.** For example: "The bass plays the root on beat 1, which is what tells your ear the chord." Or: "The melody lands on chord tones 70% of the time; the rest are passing notes." Each note is labelled chord tone or passing/neighbour against the recognised chords.
- **UI:** a lens switcher with Melody, Bass, Harmony and Chords. The default view shows only the melody and the chord ribbon. Tapping a lens solos that stem's audio.

---

## Critical files

- **New:**
  - `backend/app/melody.py`, `timing.py`, `llm.py` and `synth.py`.
  - The `backend/app/harmoniser/` package: `vocab.py`, `scoring.py`, `prior.py`, `search.py` and `reasons.py`.
  - `backend/app/data/progression_prior.json` and `scripts/build_progression_prior.py`.
  - Tests for each of the above.
- **Changed:**
  - `backend/app/main.py`: the `/analyze` shape, plus the new `/harmonise` and `/backing` endpoints.
  - `backend/requirements.txt`: add the Gemini client.
  - `app/lib/models/harmony.dart`, `session/session_controller.dart`, `screens/views/results_view.dart`, `screens/views/listening_view.dart`, and `widgets/contour/*`.
  - `docs/concepts.md`, `PRODUCT.md` and `DESIGN.md`.
- **Reused:** from `harmony.py`, `without_overtones`, `_describe_key`, `_roman` and `_viterbi` (Part 2); the function wording in `explain.py`; the Basic Pitch model loading in `main.py`.

## Verification (Part 1)

1. `backend/venv/bin/pytest`: all unit and golden-melody tests pass, and Safe matches the reference harmonisation on at least ~75% of bars across the golden set.
2. `flutter analyze` and `flutter test` in `app/` pass.
3. Run the app end to end at the local web build:
   - Hum Twinkle and Happy Birthday, with and without the click.
   - Check the grid, key, three cards, backing playback under the take, the nudge controls re-suggesting, and the "why" sheets.
   - Check Bold with and without `GEMINI_API_KEY` set.
4. Render each new results state in a widget test, the same harness used for the Stitch review, and compare against the design.
