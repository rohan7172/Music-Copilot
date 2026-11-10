"""The harmoniser: suggests chord progressions that fit a melody.

`harmonise()` is the entry point: melody + beat grid + key in, three
progressions (Safe, Colourful and Surprising/Bold) with reasons out.
"""

from app.harmoniser import reasons, scoring
from app.harmoniser.prior import load_prior
from app.harmoniser.search import Path, pick_three, score_fixed
from app.harmoniser.vocab import Chord, Key, parse_roman
from app.timing import BeatGrid

__all__ = ["harmonise", "describe_path", "Key", "parse_roman", "score_fixed"]


def describe_path(kind: str, path: Path, slots, key: Key, source: str = "theory") -> dict:
    chords = list(path.chords)
    out = []
    for i, (step, slot) in enumerate(zip(path.steps, slots)):
        prev = chords[i - 1] if i > 0 else None
        c = step.chord
        out.append(
            {
                "bar": slot.index,
                "start_time": round(slot.start, 3),
                "end_time": round(slot.end, 3),
                "symbol": c.symbol(key),
                "root": c.root_name(key),
                "quality": c.quality,
                "pitch_classes": sorted(c.pcs, key=lambda pc: (pc - c.root) % 12),
                "roman": c.roman,
                "function": c.function,
                "kind": c.kind,
                "fit": reasons.fit_label(c, slot, step.fit),
                "reasons": reasons.chord_reasons(c, slot, prev, key, step.cadence),
            }
        )
    return {
        "kind": kind,
        "source": source,
        "character": reasons.character(kind, chords, key),
        "score": round(path.score, 2),
        "chords": out,
    }


def harmonise(
    melody: list[dict],
    grid: BeatGrid,
    key: dict,
    per_bar: int = 1,
) -> dict:
    """Three progressions for the melody, plus one insight. The third is
    the corpus "surprising" option; the LLM's Bold one replaces it when
    available (see app.llm)."""
    k = Key.from_dict(key)
    slots = scoring.build_slots(melody, grid, per_bar)
    if not slots:
        return {"progressions": [], "insight": None}
    prior = load_prior()
    picked = pick_three(slots, k, prior)
    progressions = [
        describe_path(kind, path, slots, k)
        for kind, path in (("safe", picked["safe"]), ("colourful", picked["colourful"]), ("bold", picked["surprising"]))
        if path is not None
    ]
    safe_chords = list(picked["safe"].chords) if picked["safe"] else []
    return {
        "progressions": progressions,
        "insight": reasons.insight(melody, slots, safe_chords, k, grid),
        "_slots": slots,
        "_key": k,
        "_picked": picked,
    }
