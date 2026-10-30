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

# Conventional display case for each scale degree in prose, independent of
# the actual chord's quality (e.g. "ii" even for a ii° or ii7).
_DEGREE_LABELS = {1: "I", 2: "ii", 3: "iii", 4: "IV", 5: "V", 6: "vi", 7: "vii°"}

_ROMAN_RE = re.compile(r"^[#b-]*([IVXivx]+)")


def explain_progression(key: dict | None, chords: list[dict]) -> dict:
    """Returns {"summary": [...], "chords": [{"text": str}, ...]} for a key and
    chords as returned by harmony.analyze_harmony.

    `summary` is a list of {"text": str} segments, read in order to form the
    overall explanation. A segment that names a specific chord also carries
    "chord_index", that chord's position in `chords` — the app uses this to
    make the reference tappable, jumping to and playing that chord."""
    if not key or not chords:
        return {
            "summary": [_seg("Not enough was played to make out a clear key or chord progression.")],
            "chords": [],
        }
    return {
        "summary": _summarize(key, chords),
        "chords": [{"text": _describe_chord(c)} for c in chords],
    }


def _seg(text: str, chord_index: int | None = None) -> dict:
    return {"text": text} if chord_index is None else {"text": text, "chord_index": chord_index}


def _scale_degree(roman: str) -> int | None:
    match = _ROMAN_RE.match(roman)
    return _DEGREE_NAMES.get(match.group(1).upper()) if match else None


def _describe_chord(chord: dict) -> str:
    blurb = _BLURBS.get(_scale_degree(chord["roman"]))
    if blurb is None:
        return chord["name"]
    return f"{chord['name']} — the {chord['roman']} chord, {blurb}"


def _summarize(key: dict, chords: list[dict]) -> list[dict]:
    # (original index in `chords`, scale degree) for each chord whose roman
    # numeral parses, so a chord-linked segment can point at the right chord
    # even if an unrecognised one sits between them.
    pairs = [(i, d) for i, c in enumerate(chords) if (d := _scale_degree(c["roman"])) is not None]
    degrees = tuple(d for _, d in pairs)
    indices = [i for i, _ in pairs]

    builder = _PATTERN_BUILDERS.get(degrees)
    if builder:
        return builder(key, indices)

    if len(degrees) >= 2:
        cadence_builder = _CADENCE_BUILDERS.get(degrees[-2:])
        if cadence_builder:
            return cadence_builder(key, indices[-2:])

    if degrees and degrees[-1] == 5:
        return [
            _seg(f"This is in {key['name']}, ending with a half cadence on the "),
            _seg(_DEGREE_LABELS[5], indices[-1]),
            _seg(" chord — left hanging on the dominant rather than resolved."),
        ]

    chord_word = "chord" if len(chords) == 1 else "chords"
    return [_seg(f"This is in {key['name']}, moving through {len(chords)} {chord_word}.")]


def _ii_v_i(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, moving through a "),
        _seg("ii", idx[0]), _seg("–"), _seg("V", idx[1]), _seg("–"), _seg("I", idx[2]),
        _seg(" progression — the classic jazz cadence, building tension through "),
        _seg("ii", idx[0]), _seg(" and "), _seg("V", idx[1]),
        _seg(" before resolving home."),
    ]


def _i_iv_v_i(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, moving through a "),
        _seg("I", idx[0]), _seg("–"), _seg("IV", idx[1]), _seg("–"), _seg("V", idx[2]),
        _seg("–"), _seg("I", idx[3]),
        _seg(" progression — the classic blues and rock shape."),
    ]


def _i_v_vi_iv(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, moving through a "),
        _seg("I", idx[0]), _seg("–"), _seg("V", idx[1]), _seg("–"), _seg("vi", idx[2]),
        _seg("–"), _seg("IV", idx[3]),
        _seg(" progression — one of pop music's most common shapes."),
    ]


def _iv_v_i(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, moving through a "),
        _seg("IV", idx[0]), _seg("–"), _seg("V", idx[1]), _seg("–"), _seg("I", idx[2]),
        _seg(" progression, moving through the subdominant and dominant back home."),
    ]


_PATTERN_BUILDERS = {
    (2, 5, 1): _ii_v_i,
    (1, 4, 5, 1): _i_iv_v_i,
    (1, 5, 6, 4): _i_v_vi_iv,
    (4, 5, 1): _iv_v_i,
}


def _authentic_cadence(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, ending with an authentic cadence ("),
        _seg("V", idx[0]), _seg("–"), _seg("I", idx[1]),
        _seg("), the strongest way to resolve."),
    ]


def _plagal_cadence(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, ending with a plagal cadence ("),
        _seg("IV", idx[0]), _seg("–"), _seg("I", idx[1]),
        _seg("), the 'Amen' cadence."),
    ]


def _deceptive_cadence(key: dict, idx: list[int]) -> list[dict]:
    return [
        _seg(f"This is in {key['name']}, ending with a deceptive cadence ("),
        _seg("V", idx[0]), _seg("–"), _seg("vi", idx[1]),
        _seg("), resolving somewhere unexpected."),
    ]


_CADENCE_BUILDERS = {
    (5, 1): _authentic_cadence,
    (4, 1): _plagal_cadence,
    (5, 6): _deceptive_cadence,
}
