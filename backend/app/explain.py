"""Plain-language explanations of a detected key and chord progression.

Rule-based, built directly from the Roman numerals `harmony.py` already
computes — no external model or API involved.
"""

import re

_DEGREE_NAMES = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7}

_BLURBS = {
    1: "tonic: home, where the music feels at rest",
    2: "supertonic: often sets up the dominant, as in a ii–V move",
    3: "mediant: a softer color chord, blending the tonic and dominant",
    4: "subdominant: moves away from home, usually heading back through the dominant",
    5: "dominant: tension that pulls back toward the tonic",
    6: "submediant: a gentler substitute for the tonic",
    7: "leading tone: tense, pulling upward into the tonic",
}

# Full-progression shapes, matched when the whole chord sequence's scale
# degrees equal the key exactly.
_PATTERNS = {
    (2, 5, 1): (
        "a ii–V–I progression — the classic jazz cadence, building tension "
        "through ii and V before resolving home"
    ),
    (1, 4, 5, 1): "a I–IV–V–I progression — the classic blues and rock shape",
    (1, 5, 6, 4): "a I–V–vi–IV progression — one of pop music's most common shapes",
    (4, 5, 1): "a IV–V–I progression, moving through the subdominant and dominant back home",
}

# Cadences, matched against just the final two chords when no full pattern fits.
_CADENCES = {
    (5, 1): "an authentic cadence (V–I), the strongest way to resolve",
    (4, 1): "a plagal cadence (IV–I), the 'Amen' cadence",
    (5, 6): "a deceptive cadence (V–vi), resolving somewhere unexpected",
}

_ROMAN_RE = re.compile(r"^[#b-]*([IVXivx]+)")


def explain_progression(key: dict | None, chords: list[dict]) -> dict:
    """Returns {"summary": str, "chords": [{"text": str}, ...]} for a key and
    chords as returned by harmony.analyze_harmony."""
    if not key or not chords:
        return {
            "summary": "Not enough was played to make out a clear key or chord progression.",
            "chords": [],
        }
    return {
        "summary": _summarize(key, chords),
        "chords": [{"text": _describe_chord(c)} for c in chords],
    }


def _scale_degree(roman: str) -> int | None:
    match = _ROMAN_RE.match(roman)
    return _DEGREE_NAMES.get(match.group(1).upper()) if match else None


def _describe_chord(chord: dict) -> str:
    blurb = _BLURBS.get(_scale_degree(chord["roman"]))
    if blurb is None:
        return chord["name"]
    return f"{chord['name']} — the {chord['roman']} chord, {blurb}"


def _summarize(key: dict, chords: list[dict]) -> str:
    degrees = tuple(d for c in chords if (d := _scale_degree(c["roman"])) is not None)

    pattern = _PATTERNS.get(degrees)
    if pattern:
        return f"This is in {key['name']}, moving through {pattern}."

    cadence = _CADENCES.get(degrees[-2:]) if len(degrees) >= 2 else None
    if cadence:
        return f"This is in {key['name']}, ending with {cadence}."

    if degrees and degrees[-1] == 5:
        return (
            f"This is in {key['name']}, ending with a half cadence — "
            "left hanging on the dominant rather than resolved."
        )

    chord_word = "chord" if len(chords) == 1 else "chords"
    return f"This is in {key['name']}, moving through {len(chords)} {chord_word}."
