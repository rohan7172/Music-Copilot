"""Turning BTC's frame-by-frame guesses into a song's chord progression.

BTC's raw output flickers (a stray sus2 for a tenth of a second), changes
mid-beat, and knows nothing about which progressions are likely. A
beat-synchronous Viterbi decoder adds what a musician uses:

- chords change only on beats, and most readily on downbeats;
- the bass note usually is the chord's root (or at least in the chord);
- some moves are far more common than others (the corpus prior from the
  harmoniser, conditioned on the song's key);
- holding a chord is the default, so one noisy beat doesn't flip it.

Pure numpy over (beats x chord states), so it's tested on made-up
probabilities without any model.
"""

import math

import numpy as np

from app.harmoniser.prior import load_prior
from app.harmoniser.vocab import QUALITIES, Key
from app.songs.btc import NUM_CLASSES, class_chord

# Chord states: every (root, quality) BTC can say, plus "no chord".
_STATE_QUALITIES = ["maj", "min", "7", "maj7", "m7", "dim", "m7b5", "aug", "sus2", "sus4"]
STATES: list[tuple[int, str] | None] = [(r, q) for r in range(12) for q in _STATE_QUALITIES] + [None]
_NO_CHORD = len(STATES) - 1

_STAY_DOWNBEAT = 0.55  # chance of keeping the chord across a bar line
_STAY_BEAT = 0.9  # ... across any other beat
_TO_OR_FROM_NONE = 0.02
_BASS_ROOT_BONUS = math.log(1.6)
_BASS_TONE_BONUS = math.log(1.15)

# Krumhansl-Kessler key profiles.
_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def _class_to_state() -> np.ndarray:
    """(170 BTC classes x states) 0/1 matrix summing classes into states."""
    m = np.zeros((NUM_CLASSES, len(STATES)))
    index = {s: i for i, s in enumerate(STATES)}
    for c in range(NUM_CLASSES):
        chord = class_chord(c)
        m[c, _NO_CHORD if chord is None else index[chord]] = 1.0
    return m


_COLLAPSE = _class_to_state()


def beat_emissions(probs: np.ndarray, frame_seconds: float, beat_times: np.ndarray, end: float) -> np.ndarray:
    """Average chord-state probability over each beat span, (beats x states).
    The last beat runs to `end`."""
    state_probs = probs @ _COLLAPSE
    bounds = list(beat_times) + [end]
    out = np.zeros((len(beat_times), len(STATES)))
    for i in range(len(beat_times)):
        a = int(bounds[i] / frame_seconds)
        b = max(a + 1, int(bounds[i + 1] / frame_seconds))
        span = state_probs[a:b]
        out[i] = span.mean(axis=0) if len(span) else state_probs[min(a, len(state_probs) - 1)]
    return out


def estimate_key(emissions: np.ndarray) -> Key:
    """Krumhansl-Schmuckler over the chord tones the song spends its time on."""
    chroma = np.zeros(12)
    for s, (state) in enumerate(STATES):
        if state is None:
            continue
        root, quality = state
        weight = emissions[:, s].sum()
        for i in QUALITIES[quality]:
            chroma[(root + i) % 12] += weight
        chroma[root] += 0.5 * weight
    z = (chroma - chroma.mean()) / (chroma.std() or 1)
    best, best_score = Key(0, "major"), -math.inf
    for tonic in range(12):
        for mode, profile in (("major", _MAJOR), ("minor", _MINOR)):
            p = np.roll(profile, tonic)
            score = float(((p - p.mean()) / p.std()) @ z)
            if score > best_score:
                best, best_score = Key(tonic, mode), score
    return best


def _token(state: tuple[int, str], key: Key) -> str:
    return f"{(state[0] - key.tonic) % 12}:{state[1]}"


def _transitions(key: Key) -> np.ndarray:
    """log P(next state | state) given a chord change, (states x states),
    from the corpus prior; the self-transition is handled separately."""
    prior = load_prior()
    n = len(STATES)
    t = np.full((n, n), -math.inf)
    for i, a in enumerate(STATES):
        row = np.full(n, -math.inf)
        for j, b in enumerate(STATES):
            if i == j:
                continue
            if a is None or b is None:
                row[j] = math.log(_TO_OR_FROM_NONE)
            else:
                row[j] = prior.log_prob(key.mode, None, _token(a, key), _token(b, key))
        finite = np.isfinite(row)
        row[finite] -= np.logaddexp.reduce(row[finite])  # normalise over the changes
        t[i] = row
    return t


def decode(
    emissions: np.ndarray,
    downbeat_flags: list[bool],
    key: Key,
    bass_pcs: list[int | None] | None = None,
) -> tuple[list[int], list[float]]:
    """The most likely chord state per beat, and how sure each beat is
    (the chosen state's share of that beat's probability)."""
    n_beats, n_states = emissions.shape
    log_e = np.log(emissions + 1e-6)
    if bass_pcs is not None:
        for i, pc in enumerate(bass_pcs):
            if pc is None:
                continue
            for s, state in enumerate(STATES):
                if state is None:
                    continue
                root, quality = state
                if root == pc:
                    log_e[i, s] += _BASS_ROOT_BONUS
                elif (pc - root) % 12 in QUALITIES[quality]:
                    log_e[i, s] += _BASS_TONE_BONUS
    change = _transitions(key)
    score = log_e[0].copy()
    back = np.zeros((n_beats, n_states), dtype=int)
    for i in range(1, n_beats):
        stay_p = _STAY_DOWNBEAT if downbeat_flags[i] else _STAY_BEAT
        stay = score + math.log(stay_p)
        moved = score[:, None] + math.log(1 - stay_p) + change  # from x to
        best_from = moved.argmax(axis=0)
        best_moved = moved[best_from, np.arange(n_states)]
        take_stay = stay >= best_moved
        back[i] = np.where(take_stay, np.arange(n_states), best_from)
        score = np.where(take_stay, stay, best_moved) + log_e[i]
    path = [int(score.argmax())]
    for i in range(n_beats - 1, 0, -1):
        path.append(int(back[i, path[-1]]))
    path.reverse()
    confidence = [float(emissions[i, s] / max(emissions[i].sum(), 1e-9)) for i, s in enumerate(path)]
    return path, confidence


def segments(path: list[int], confidence: list[float], beat_times: np.ndarray, end: float) -> list[dict]:
    """Merged chord spans: {state, start, end, confidence}; no-chord spans
    are left out."""
    out = []
    bounds = list(beat_times) + [end]
    for i, s in enumerate(path):
        if out and out[-1]["state"] == s:
            out[-1]["end"] = bounds[i + 1]
            out[-1]["_conf"].append(confidence[i])
            continue
        out.append({"state": s, "start": bounds[i], "end": bounds[i + 1], "_conf": [confidence[i]]})
    return [
        {"state": STATES[o["state"]], "start": o["start"], "end": o["end"], "confidence": float(np.mean(o["_conf"]))}
        for o in out
        if STATES[o["state"]] is not None
    ]
