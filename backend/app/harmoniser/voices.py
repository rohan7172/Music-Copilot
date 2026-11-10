"""Harmony lines: a second voice to sing with the melody.

The progressions answer "what chords go under this tune?". This answers
"what could a second singer sing with it?", for one chosen progression.

Each harmony note is picked with the same kind of reasoning a choir
arranger uses, written as costs and solved for the whole line at once:

- **Against the melody**: thirds and sixths blend; a second, a seventh or
  a tritone against the tune rubs; a unison or an octave isn't harmony.
- **Against the chord**: a harmony note that's in the chord sounds
  settled; one that isn't is fine passing by on a weak beat, but not held
  or on beat 1.
- **Against itself**: a line should be singable — small steps, few leaps,
  and no "parallel fifths/octaves" with the tune (two voices moving in
  perfect fifths sound like one voice, so the harmony vanishes).

Scoring every note choice against its neighbours is a shortest-path
problem through a grid of (note, candidate pitch), solved with the
Viterbi algorithm — the same "best path through time" idea as the song
chord decoder (`app/songs/decode.py`), here over pitches instead of chords.

Three styles come from three sets of weights:

- **High harmony**: mostly a third above, like a classic duet.
- **Low harmony**: under the tune in thirds and sixths.
- **Held line**: long notes from the chords that only move when they
  must, like backing singers' "oohs".
"""

from dataclasses import dataclass

from app.harmoniser.vocab import Key, pc_of
from app.notes import midi_to_note_name
from app.timing import BeatGrid

_SCALES = {"major": (0, 2, 4, 5, 7, 9, 11), "minor": (0, 2, 3, 5, 7, 8, 10)}

# A new phrase starts after a rest this long: the harmony can jump freely.
_PHRASE_GAP = 0.45
# Held-line notes this close together on the same pitch are one held note.
_TIE_GAP = 0.3


@dataclass(frozen=True)
class Style:
    id: str
    name: str
    character: str
    above: bool
    lowest: int  # how far from the melody, in semitones
    widest: int
    # Cost by interval to the melody (semitones, not reduced to an octave).
    interval_cost: dict[int, float]
    # Weight on a non-chord harmony note held or on a strong beat.
    chord_weight: float
    # Moving: "parallel" pays for not moving like the melody; "still" pays
    # for any motion at all.
    motion: str
    motion_weight: float
    tie_notes: bool


HIGH = Style(
    id="high",
    name="High harmony",
    character="a third above you, the classic duet sound",
    above=True,
    lowest=3,
    widest=9,
    interval_cost={3: 0.0, 4: 0.0, 5: 1.4, 7: 1.8, 8: 0.9, 9: 0.9},
    chord_weight=2.0,
    motion="parallel",
    motion_weight=0.3,
    tie_notes=False,
)
LOW = Style(
    id="low",
    name="Low harmony",
    character="under the tune, in thirds and sixths",
    above=False,
    lowest=3,
    widest=9,
    interval_cost={3: 0.0, 4: 0.0, 5: 1.4, 7: 1.2, 8: 0.25, 9: 0.25},
    chord_weight=2.0,
    motion="parallel",
    motion_weight=0.3,
    tie_notes=False,
)
HELD = Style(
    id="held",
    name="Held line",
    character="long notes from the chords, moving only when they must",
    above=False,
    lowest=3,
    widest=12,
    interval_cost={3: 0.0, 4: 0.0, 5: 0.5, 7: 0.4, 8: 0.1, 9: 0.1, 12: 3.0},
    chord_weight=4.0,
    motion="still",
    motion_weight=0.55,
    tie_notes=True,
)
STYLES = (HIGH, LOW, HELD)


def _dissonance(semitones: int) -> float:
    """How much two notes this far apart rub, sounded together."""
    ic = semitones % 12
    if ic in (1, 11):
        return 6.0  # a minor second / major seventh: a hard clash
    if ic in (2, 10):
        return 2.5  # a second / minor seventh: a soft rub
    if ic == 6:
        return 3.0  # the tritone
    if ic == 0:
        return 4.0  # a unison or octave: the same note, not harmony
    return 0.0


@dataclass
class _Spot:
    """One melody note, with what the harmony needs to know about it."""

    midi: int
    start: float
    end: float
    chord: frozenset[int] | None
    strength: float  # metric strength where it starts, 0..1
    beats: float  # how long it lasts, in beats


def _spots(melody: list[dict], chords: list[dict], grid: BeatGrid | None) -> list[_Spot]:
    beat = grid.beat_length if grid else 0.6
    out = []
    for n in sorted(melody, key=lambda n: n["start_time"]):
        start, end = float(n["start_time"]), float(n["end_time"])
        if end <= start:
            continue
        # The chord this note mostly sounds over.
        best, overlap = None, 0.0
        for c in chords:
            o = min(end, float(c["end_time"])) - max(start, float(c["start_time"]))
            if o > overlap:
                best, overlap = c, o
        out.append(
            _Spot(
                midi=int(n["midi_pitch"]),
                start=start,
                end=end,
                chord=frozenset(int(pc) % 12 for pc in best["pitch_classes"]) if best else None,
                strength=grid.strength(start) if grid else 0.5,
                beats=(end - start) / beat,
            )
        )
    return out


def _candidates(spot: _Spot, style: Style, scale: frozenset[int]) -> list[int]:
    sign = 1 if style.above else -1
    out = []
    for d in range(style.lowest, style.widest + 1):
        h = spot.midi + sign * d
        # In the key, or a note of the chord (a secondary dominant's
        # raised note, say): never a note neither of them has.
        if h % 12 in scale or (spot.chord and h % 12 in spot.chord):
            out.append(h)
    return out


def _note_cost(h: int, spot: _Spot, style: Style, scale: frozenset[int]) -> float:
    gap = abs(h - spot.midi)
    cost = style.interval_cost.get(gap, 1.0)
    rub = _dissonance(gap)
    # A short note off the beat can rub a little in passing.
    if rub and rub < 4.0 and spot.strength < 0.5 and spot.beats < 0.75:
        rub *= 0.5
    cost += rub
    if spot.chord is not None and h % 12 not in spot.chord:
        exposure = min(1.0, spot.strength + min(spot.beats, 2.0) / 2)
        cost += style.chord_weight * exposure + 0.2
    if h % 12 not in scale:
        cost += 0.3
    return cost


def _move_cost(prev_h: int, h: int, prev: _Spot, spot: _Spot, style: Style) -> float:
    if spot.start - prev.end > _PHRASE_GAP:
        return 0.0  # a new phrase: start wherever sounds best
    step = h - prev_h
    if style.motion == "parallel":
        cost = style.motion_weight * abs(step - (spot.midi - prev.midi))
    else:
        cost = style.motion_weight * abs(step)
    if abs(step) > 7:
        cost += 0.6 * (abs(step) - 7)  # a big leap is hard to sing
    # Parallel fifths/octaves: both voices move, keeping a perfect interval.
    before = abs(prev_h - prev.midi) % 12
    now = abs(h - spot.midi) % 12
    if before == now and now in (0, 7) and step != 0 and spot.midi != prev.midi:
        cost += 2.0
    return cost


def harmony_line(
    melody: list[dict],
    chords: list[dict],
    key: dict,
    style: Style,
    grid: BeatGrid | None = None,
) -> list[dict]:
    """The best harmony line in `style` for the melody over `chords`,
    as note dicts shaped like Basic Pitch's."""
    k = Key(pc_of(key["tonic"]), key["mode"])
    scale = frozenset((k.tonic + i) % 12 for i in _SCALES.get(k.mode, _SCALES["major"]))
    spots = _spots(melody, chords, grid)
    if not spots:
        return []

    # Viterbi: best[i][h] = cheapest line ending on pitch h at note i.
    options = [_candidates(s, style, scale) or [s.midi + (4 if style.above else -5)] for s in spots]
    best = [{h: _note_cost(h, spots[0], style, scale) for h in options[0]}]
    back: list[dict[int, int]] = [{}]
    for i in range(1, len(spots)):
        here, came = {}, {}
        for h in options[i]:
            own = _note_cost(h, spots[i], style, scale)
            prev_h, total = min(
                ((p, c + _move_cost(p, h, spots[i - 1], spots[i], style)) for p, c in best[-1].items()),
                key=lambda pc: pc[1],
            )
            here[h], came[h] = total + own, prev_h
        best.append(here)
        back.append(came)

    h = min(best[-1], key=best[-1].get)
    pitches = [h]
    for i in range(len(spots) - 1, 0, -1):
        h = back[i][h]
        pitches.append(h)
    pitches.reverse()

    line = [
        {"midi_pitch": h, "start_time": s.start, "end_time": s.end}
        for h, s in zip(pitches, spots)
    ]
    if style.tie_notes:
        tied = [line[0]]
        for n in line[1:]:
            last = tied[-1]
            if n["midi_pitch"] == last["midi_pitch"] and n["start_time"] - last["end_time"] < _TIE_GAP:
                last["end_time"] = n["end_time"]
            else:
                tied.append(n)
        line = tied
    return [
        {
            "pitch": midi_to_note_name(n["midi_pitch"]),
            "midi_pitch": n["midi_pitch"],
            "start_time": round(n["start_time"], 3),
            "end_time": round(n["end_time"], 3),
            "confidence": 1.0,
        }
        for n in line
    ]


def _detail(style: Style, line: list[dict], melody: list[dict], chords: list[dict]) -> str:
    """One true sentence about the line, measured from it."""
    if style.tie_notes:
        return (
            f"It changes note {len(line)} times against your {len(melody)}, "
            "holding notes of each chord so the tune and the chords sound like one."
        )
    names = {5: "a fourth", 6: "a tritone", 7: "a fifth", 8: "a sixth", 9: "a sixth"}
    thirds, others = 0, {}
    for h, m in zip(line, sorted(melody, key=lambda n: n["start_time"])):
        gap = abs(h["midi_pitch"] - m["midi_pitch"])
        if gap in (3, 4):
            thirds += 1
        elif gap in names:
            others[names[gap]] = others.get(names[gap], 0) + 1
    share = round(100 * thirds / max(1, len(line)))
    where = "above" if style.above else "below"
    if not others:
        return f"Every note is a third {where} yours, bent to stay in the key."
    other = max(others, key=others.get)
    return (
        f"{share}% of its notes are a third {where} yours; where a third would rub "
        f"against the chord, it mostly moves to {other} instead."
    )


def _range(line: list[dict]) -> str:
    lo = min(line, key=lambda n: n["midi_pitch"])["pitch"]
    hi = max(line, key=lambda n: n["midi_pitch"])["pitch"]
    return lo if lo == hi else f"{lo}–{hi}"


def harmonies(
    melody: list[dict],
    chords: list[dict],
    key: dict | None,
    grid: BeatGrid | None = None,
) -> list[dict]:
    """Every style's harmony line for the melody over one progression."""
    if not melody or not key:
        return []
    out = []
    for style in STYLES:
        line = harmony_line(melody, chords, key, style, grid)
        if not line:
            continue
        out.append(
            {
                "id": style.id,
                "name": style.name,
                "character": style.character,
                "detail": _detail(style, line, melody, chords),
                "range": _range(line),
                "notes": line,
            }
        )
    return out
