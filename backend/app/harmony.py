"""Key and chord analysis over the notes Basic Pitch found.

Chords are found by matching the pitch classes sounding at each moment
against chord templates, then smoothing over time so a chord holds until the
harmony really changes. When fewer than three notes are sounding, recently
released notes count too, so arpeggios register as chords, not just block
chords.
"""

import bisect
import math

import numpy as np
from music21 import chord as m21chord
from music21 import key as m21key
from music21 import note as m21note
from music21 import roman, stream

_SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
_FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

# Intervals above the root, display suffix, and a prior that nudges ties
# toward the more common chord.
_QUALITIES = {
    "maj": ((0, 4, 7), "", 1.0),
    "min": ((0, 3, 7), "m", 1.0),
    "7": ((0, 4, 7, 10), "7", 0.98),
    "maj7": ((0, 4, 7, 11), "maj7", 0.97),
    "min7": ((0, 3, 7, 10), "m7", 0.97),
    "dim": ((0, 3, 6), "dim", 0.96),
    "m7b5": ((0, 3, 6, 10), "m7b5", 0.95),
    "sus2": ((0, 2, 7), "sus2", 0.94),
    "sus4": ((0, 5, 7), "sus4", 0.94),
    "aug": ((0, 4, 8), "aug", 0.92),
}

_FRAME = 0.05  # seconds per analysis frame
_HOLD = 0.6  # how long a released note keeps counting, for arpeggios
_ACTIVE = 0.15  # weight above which a pitch class counts as present
_MIN_COVERAGE = 0.8  # share of the sounding weight a chord must explain
_SWITCH_PENALTY = 1.0  # log-score cost of changing chord between frames
_MIN_CHORD = 0.2  # seconds; shorter chords are dropped

_TEMPLATES = [
    (root, quality, intervals, prior)
    for root in range(12)
    for quality, (intervals, _, prior) in _QUALITIES.items()
]


def analyze_harmony(notes: list[dict]) -> dict:
    """Returns {"key": ..., "chords": [...]} for notes as returned by /analyze."""
    notes = without_overtones(notes)
    if not notes:
        return {"key": None, "chords": []}
    basses = _bass_spans(notes)
    detected_key = _detect_key(notes, basses)
    return {
        "key": _describe_key(detected_key),
        "chords": _detect_chords(notes, basses, detected_key),
    }


def without_overtones(notes: list[dict]) -> list[dict]:
    """Drops notes that are really the overtone of a louder note.

    Basic Pitch sometimes reports a note's third harmonic (an octave and a
    fifth up) as a note of its own: starting at the same moment, at well
    under the real note's loudness, and fading first. Left in, it shows as a
    stray note and adds a pitch class that isn't really there. A genuinely
    played note at that interval is kept, since it's about as loud and lasts.
    """
    def is_overtone(n):
        return any(
            m["midi_pitch"] == n["midi_pitch"] - 19
            and abs(m["start_time"] - n["start_time"]) <= 0.08
            and n["confidence"] < 0.65 * m["confidence"]
            and n["end_time"] < m["end_time"]
            for m in notes
        )

    return [n for n in notes if not is_overtone(n)]


def _detect_key(notes: list[dict], basses: list[tuple[dict, float]]) -> m21key.Key:
    """Krumhansl-Schmuckler key finding, weighting notes by duration.

    Bass notes count for as long as they hold the harmony, not just as long
    as they were reported sounding.
    """
    bass_until = {id(b): until for b, until in basses}
    s = stream.Stream()
    for n in notes:
        end = max(n["end_time"], bass_until.get(id(n), 0))
        length = max(end - n["start_time"], 0.05)
        s.insert(n["start_time"], m21note.Note(midi=n["midi_pitch"], quarterLength=length))
    return s.analyze("krumhansl")


def _pitch_names(k: m21key.Key) -> list[str]:
    return _FLAT_NAMES if k.sharps < 0 else _SHARP_NAMES


def _describe_key(k: m21key.Key) -> dict:
    tonic = k.tonic.name.replace("-", "b")
    return {
        "tonic": tonic,
        "mode": k.mode,
        "name": f"{tonic} {k.mode}",
        "confidence": round(float(k.correlationCoefficient), 3),
    }


def _chroma(notes: list[dict], basses: list[tuple[dict, float]]) -> tuple[np.ndarray, np.ndarray]:
    """Per-frame pitch-class weights (frames x 12) and the lowest sounding pitch class.

    Released notes only count while fewer than three pitch classes are
    actually sounding (an arpeggio), so a block chord doesn't bleed into the
    next one. A new lowest note (a new bass) clears them, since it usually
    starts the next chord. The bass itself keeps counting until the next bass
    arrives: it defines the harmony even after it fades (Basic Pitch often
    ends low notes early).
    """
    duration = max(n["end_time"] for n in notes) + _HOLD
    frames = math.ceil(duration / _FRAME)
    sounding = np.zeros((frames, 12))
    held = np.zeros((frames, 12))
    lowest = np.full(frames, 128)

    by_start = sorted(notes, key=lambda n: n["start_time"])
    resets = []
    for i, n in enumerate(by_start):
        recent = [m["midi_pitch"] for m in by_start[:i] if m["end_time"] + _HOLD > n["start_time"]]
        if recent and n["midi_pitch"] < min(recent):
            resets.append(n["start_time"])

    for n in notes:
        pc = n["midi_pitch"] % 12
        weight = min(1.0, max(0.2, n["confidence"] / 0.6))
        start = int(n["start_time"] / _FRAME)
        end = int(n["end_time"] / _FRAME)
        hold_end = min(frames, end + int(_HOLD / _FRAME))
        reset = bisect.bisect_left(resets, n["end_time"])
        if reset < len(resets):
            hold_end = min(hold_end, int(resets[reset] / _FRAME))
        # max (not sum) so octave doublings don't dominate.
        for f in range(start, min(frames, end)):
            sounding[f, pc] = max(sounding[f, pc], weight)
            lowest[f] = min(lowest[f], n["midi_pitch"])
        for f in range(end, hold_end):
            fade = 1 - 0.5 * (f - end) / (hold_end - end)
            held[f, pc] = max(held[f, pc], weight * fade)
    bass_memory = np.zeros((frames, 12))
    remembered = np.full(frames, -1)
    for b, until in basses:
        for f in range(int(b["start_time"] / _FRAME), min(frames, int(until / _FRAME))):
            bass_memory[f, b["midi_pitch"] % 12] = 0.7
            remembered[f] = b["midi_pitch"] % 12

    arpeggio = (sounding > _ACTIVE).sum(axis=1) < 3
    chroma = np.where(arpeggio[:, None], np.maximum(sounding, held), sounding)
    chroma = np.maximum(chroma, bass_memory)
    bass = np.where(lowest < 128, lowest % 12, remembered)
    return chroma, bass


def _bass_spans(notes: list[dict]) -> list[tuple[dict, float]]:
    """Bass notes, each with the time it holds the harmony until: the next
    bass note, or when the notes above it have all ended."""
    by_start = sorted(notes, key=lambda n: n["start_time"])
    basses = _bass_notes(by_start)
    spans = []
    for i, b in enumerate(basses):
        next_start = basses[i + 1]["start_time"] if i + 1 < len(basses) else math.inf
        # Everything sounding over this bass, including notes that began a
        # moment before it (onsets are rarely reported exactly together).
        above = [
            n["end_time"]
            for n in by_start
            if n["start_time"] < next_start and n["end_time"] > b["start_time"]
        ]
        spans.append((b, min(next_start, max(above))))
    return spans


def _bass_notes(by_start: list[dict]) -> list[dict]:
    """Notes that start a new bass: the lowest of the notes starting together,
    and no higher than anything still sounding from before."""
    basses = []
    for n in by_start:
        if basses and abs(basses[-1]["start_time"] - n["start_time"]) <= 0.05:
            continue  # this onset already has its bass
        together = [m for m in by_start if abs(m["start_time"] - n["start_time"]) <= 0.05]
        lowest = min(together, key=lambda m: m["midi_pitch"])
        ringing = [
            m["midi_pitch"]
            for m in by_start
            if m["start_time"] < n["start_time"] - 0.05 and m["end_time"] > n["start_time"]
        ]
        if all(lowest["midi_pitch"] <= p for p in ringing):
            basses.append(lowest)
    return basses


def _frame_scores(chroma: np.ndarray, bass: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Score of each chord template (plus a final "no chord" state) per frame,
    and which templates were fully heard in that frame (not just carried on)."""
    frames = chroma.shape[0]
    scores = np.full((frames, len(_TEMPLATES) + 1), 0.02)
    heard = np.zeros((frames, len(_TEMPLATES)), dtype=bool)
    for f in range(frames):
        v = chroma[f]
        total = v.sum()
        active = int((v > _ACTIVE).sum())
        if total <= 0:
            scores[f, -1] = 1.0
            continue
        if active < 3:
            # Too few notes to name a chord, but a chord that contains them
            # can carry on through (e.g. between arpeggio notes), preferably
            # the one built on the bass.
            scores[f, -1] = 0.6
            sounding = {pc for pc in range(12) if v[pc] > _ACTIVE}
            for t, (root, _, intervals, _) in enumerate(_TEMPLATES):
                if sounding <= {(root + i) % 12 for i in intervals}:
                    scores[f, t] = 0.62 + (0.05 if bass[f] == root else 0)
            continue
        scores[f, -1] = 0.55
        for t, (root, _, intervals, prior) in enumerate(_TEMPLATES):
            tones = [(root + i) % 12 for i in intervals]
            coverage = v[tones].sum() / total
            # Every tone must sound, except that a seventh chord may drop its
            # fifth, as real voicings often do.
            required = [pc for i, pc in zip(intervals, tones) if not (len(tones) == 4 and i == 7)]
            present = sum(v[pc] > _ACTIVE for pc in tones) / len(tones)
            if coverage < _MIN_COVERAGE or any(v[pc] <= _ACTIVE for pc in required):
                continue
            score = prior * (0.6 * coverage + 0.4 * present)
            if bass[f] == root:
                score += 0.05  # the root in the bass is the likeliest reading
            scores[f, t] = score
            heard[f, t] = True
    return scores, heard


def _viterbi(scores: np.ndarray) -> np.ndarray:
    """Most likely state per frame, paying a penalty for every change."""
    log_scores = np.log(scores)
    best = log_scores[0].copy()
    back = np.zeros(scores.shape, dtype=int)
    for f in range(1, scores.shape[0]):
        switch_from = int(best.argmax())
        switch_score = best[switch_from] - _SWITCH_PENALTY
        stay = best >= switch_score
        back[f] = np.where(stay, np.arange(scores.shape[1]), switch_from)
        best = np.where(stay, best, switch_score) + log_scores[f]
    path = np.zeros(scores.shape[0], dtype=int)
    path[-1] = int(best.argmax())
    for f in range(scores.shape[0] - 1, 0, -1):
        path[f - 1] = back[f, path[f]]
    return path


def _detect_chords(notes: list[dict], basses: list[tuple[dict, float]], k: m21key.Key) -> list[dict]:
    chroma, bass = _chroma(notes, basses)
    scores, heard = _frame_scores(chroma, bass)
    path = _viterbi(scores)
    names = _pitch_names(k)
    last_note_end = max(n["end_time"] for n in notes)

    chords = []
    start = 0
    for f in range(1, len(path) + 1):
        if f < len(path) and path[f] == path[start]:
            continue
        state = path[start]
        start_time = start * _FRAME
        end_time = min(f * _FRAME, last_note_end)
        # Carrying a chord through sparse moments is fine; inventing one isn't,
        # so every chord must be fully heard at least once.
        if (
            state < len(_TEMPLATES)
            and end_time - start_time >= _MIN_CHORD
            and heard[start:f, state].any()
        ):
            root, quality, intervals, _ = _TEMPLATES[state]
            chords.append(_describe_chord(root, quality, intervals, start_time, end_time, k, names))
        start = f
    return chords


def _describe_chord(root, quality, intervals, start_time, end_time, k, names) -> dict:
    tones = [names[(root + i) % 12] for i in intervals]
    return {
        "name": names[root] + _QUALITIES[quality][1],
        "root": names[root],
        "quality": quality,
        "roman": _roman(root, quality, intervals, k),
        "notes": tones,
        "pitch_classes": [(root + i) % 12 for i in intervals],
        "start_time": round(start_time, 3),
        "end_time": round(end_time, 3),
    }


def _roman(root: int, quality: str, intervals, k: m21key.Key) -> str:
    """Roman numeral of the chord in the key, e.g. "vi" or "V7"."""
    if quality.startswith("sus"):
        # music21 reads sus chords as inversions of other chords, so name the
        # scale degree from the major triad on the root and add the suffix.
        base = _roman(root, "maj", (0, 4, 7), k)
        return base + quality
    pitches = [m21note.Note(midi=48 + root + i).pitch for i in intervals]
    figure = roman.romanNumeralFromChord(m21chord.Chord(pitches), k).figure
    return figure.replace("o", "°")
