"""Beam search over the slots for whole progressions, and the pick of
three different ones: Safe, Colourful and Surprising.

Each kind is the same search with different weights (a "profile"), then
filtered so the three really differ (at least a third of the slots).
"""

import math
from dataclasses import dataclass, field

from app.harmoniser import scoring
from app.harmoniser.prior import ProgressionPrior
from app.harmoniser.vocab import Chord, Key, vocabulary


# Chord kinds that count as a genuine surprise, not just a richer voicing.
_SURPRISE_KINDS = ("borrowed", "secondary", "chromatic")


@dataclass(frozen=True)
class Profile:
    melody: float = 3.0
    key: float = 1.0
    prior: float = 0.6
    motion: float = 1.0
    cadence: float = 1.0
    colour_bonus: float = 0.0  # reward for each non-plain chord
    surprise_bonus: float = 0.0  # reward for borrowed / secondary / chromatic chords


SAFE = Profile(key=2.5, prior=0.8)
COLOURFUL = Profile(key=0.45, prior=0.5, colour_bonus=0.3)
SURPRISING = Profile(key=0.2, prior=0.25, surprise_bonus=0.7)


@dataclass
class Step:
    chord: Chord
    fit: float
    key_cost: float
    log_p: float
    motion: float
    cadence: float
    repeat: float


@dataclass
class Path:
    score: float
    steps: list[Step] = field(default_factory=list)

    @property
    def chords(self) -> tuple[Chord, ...]:
        return tuple(s.chord for s in self.steps)


# Holding a chord into the next slot isn't a "move": chord corpora list
# changes, not held bars, so the corpus can't judge it. A held chord gets
# this neutral value instead, and `scoring.repetition` decides when a hold
# has gone on too long.
HOLD_LOG_P = math.log(0.12)


def _log_p(prior: ProgressionPrior, key: Key, chords: tuple[Chord, ...], c: Chord) -> float:
    prev = chords[-1] if chords else None
    if prev == c:
        return HOLD_LOG_P
    # Skip back over held chords so the context is the last two changes.
    changes = [x for i, x in enumerate(chords) if i == 0 or chords[i - 1] != x]
    prev1 = changes[-1] if changes else None
    prev2 = changes[-2] if len(changes) > 1 else None
    return prior.log_prob(
        key.mode,
        prev2.token(key) if prev2 else None,
        prev1.token(key) if prev1 else None,
        c.token(key),
    )


def _candidates(slot: scoring.Slot, vocab: list[Chord], limit: int = 14) -> list[Chord]:
    """The chords worth considering for a slot: the best melody fits, plus
    I and V so the search can always cadence."""
    if slot.empty:
        return vocab
    ranked = sorted(vocab, key=lambda c: scoring.melody_fit(c, slot) - 0.3 * scoring.key_cost(c), reverse=True)
    chosen = ranked[:limit]
    for c in vocab[:7]:
        if c.function in ("tonic", "dominant") and c.kind == "diatonic" and c not in chosen:
            if (c.root - vocab[0].root) % 12 in (0, 7):
                chosen.append(c)
    return chosen


def search(
    slots: list[scoring.Slot],
    key: Key,
    prior: ProgressionPrior,
    profile: Profile,
    beam: int = 60,
    vocab: list[Chord] | None = None,
) -> list[Path]:
    """The best whole progressions under a profile, best first."""
    vocab = vocab or vocabulary(key)
    fits = [{c: scoring.melody_fit(c, s) for c in vocab} for s in slots]
    paths = [Path(score=0.0)]
    for i, slot in enumerate(slots):
        options = _candidates(slot, vocab)
        grown: list[Path] = []
        for path in paths:
            chords = path.chords
            prev = chords[-1] if chords else None
            for c in options:
                fit = fits[i][c]
                k = scoring.key_cost(c)
                log_p = _log_p(prior, key, chords, c)
                motion = scoring.root_motion(prev, c)
                cad = scoring.cadence(prev, c, slot, key, first=i == 0)
                rep = scoring.repetition(chords, c, slot)
                gain = (
                    profile.melody * fit
                    - profile.key * k
                    + profile.prior * log_p
                    + profile.motion * motion
                    + profile.cadence * cad
                    + rep
                    + (profile.colour_bonus if c.is_colour else 0.0)
                    + (profile.surprise_bonus if c.kind in _SURPRISE_KINDS else 0.0)
                )
                grown.append(
                    Path(score=path.score + gain, steps=path.steps + [Step(c, fit, k, log_p, motion, cad, rep)])
                )
        grown.sort(key=lambda p: p.score, reverse=True)
        # Keep the beam varied: at most a few paths ending in the same chord.
        kept, per_end = [], {}
        for p in grown:
            end = p.chords[-1]
            if per_end.get(end, 0) >= max(3, beam // 8):
                continue
            per_end[end] = per_end.get(end, 0) + 1
            kept.append(p)
            if len(kept) >= beam:
                break
        paths = kept
    return paths


def differs(a: tuple[Chord, ...], b: tuple[Chord, ...]) -> int:
    return sum(x != y for x, y in zip(a, b))


def pick_three(slots, key, prior) -> dict[str, Path | None]:
    """Safe, Colourful and Surprising, each required to differ from the
    ones before it in at least a third of the slots."""
    n = len(slots)
    need = max(1, math.ceil(n / 3))
    safe_paths = search(slots, key, prior, SAFE)
    safe = safe_paths[0] if safe_paths else None
    if safe is None:
        return {"safe": None, "colourful": None, "surprising": None}

    colourful = next(
        (
            p
            for p in search(slots, key, prior, COLOURFUL)
            if any(c.is_colour for c in p.chords)
            and differs(p.chords, safe.chords) >= need
            and p.chords[-1].function == "tonic"
        ),
        None,
    )

    taken = [safe.chords] + ([colourful.chords] if colourful else [])
    # A surprise is one or two well-placed turns, so it only has to differ
    # in a quarter of the slots.
    need_surprise = max(1, math.ceil(n / 4))
    surprising = next(
        (
            p
            for p in search(slots, key, prior, SURPRISING, beam=90)
            if all(differs(p.chords, t) >= need_surprise for t in taken)
            and any(c.kind in _SURPRISE_KINDS for c in p.chords)
            and p.chords[-1].function == "tonic"
            and sum(c.kind == "sus" for c in p.chords) <= max(1, n // 4)
            and all(s.fit >= 0.25 or slot.empty for s, slot in zip(p.steps, slots))
            and not any(scoring.has_strong_clash(s.chord, slot) for s, slot in zip(p.steps, slots))
        ),
        None,
    )
    return {"safe": safe, "colourful": colourful, "surprising": surprising}


def score_fixed(slots, key, prior, chords: list[Chord], profile: Profile = COLOURFUL) -> Path:
    """Scores a given progression (e.g. one an LLM proposed) with the same
    terms, so it can be compared with and explained like the others."""
    path = Path(score=0.0)
    for i, (slot, c) in enumerate(zip(slots, chords)):
        prev = path.chords[-1] if path.steps else None
        fit = scoring.melody_fit(c, slot)
        k = scoring.key_cost(c)
        log_p = _log_p(prior, key, path.chords, c)
        motion = scoring.root_motion(prev, c)
        cad = scoring.cadence(prev, c, slot, key, first=i == 0)
        rep = scoring.repetition(path.chords, c, slot)
        gain = profile.melody * fit - profile.key * k + profile.prior * log_p + profile.motion * motion + profile.cadence * cad + rep
        path = Path(score=path.score + gain, steps=path.steps + [Step(c, fit, k, log_p, motion, cad, rep)])
    return path
