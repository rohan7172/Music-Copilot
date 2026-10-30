"""The harmoniser's score terms.

A progression's score is the sum, over its slots, of

    w_m * M(chord, melody notes)  how well the chord fits the tune here
  - w_k * K(chord)                how far the chord is from the plain key
  + w_p * log P(chord | before)   how natural the move is (corpus prior)
  + w_r * R(previous, chord)      root-motion habits (down a fifth, by step)
  + w_c * C(...)                  cadence bonus at phrase ends

Every term is a plain function so each one can be tested and quoted back
as a reason.
"""

from dataclasses import dataclass, field

from app.harmoniser.vocab import KEY_COST, Chord, Key
from app.timing import BeatGrid

# Notes over a chord that read as "colour" rather than as clashes, by
# semitones above the root, with how much credit each gets. A plain triad
# makes a weaker colour than a seventh chord already built around it: a
# held E over F is only "dreamy" once the chord is Fmaj7, where E is a
# chord tone.
_COLOUR = {
    "triad": {2: 0.35, 9: 0.35, 11: 0.1},  # add9, add6, an unprepared major 7th
    "major7": {2: 0.45, 9: 0.45},  # 9th, 13th
    "dominant": {2: 0.45, 9: 0.45},  # 9th, 13th
    "minor": {2: 0.4, 5: 0.35, 10: 0.2},  # 9th, 11th, minor 7th
    "minor7": {2: 0.45, 5: 0.45},  # 9th, 11th
    "suspended": {2: 0.3, 9: 0.3},
    "diminished": {},
}
_FAMILY = {
    "maj": "triad", "maj7": "major7", "aug": "triad", "7": "dominant",
    "min": "minor", "m7": "minor7", "dim": "diminished", "m7b5": "diminished",
    "sus4": "suspended", "sus2": "suspended",
}
_INTERVAL_NAME = {1: "♭9th", 2: "9th", 3: "♯9th", 5: "11th", 6: "♯11th",
                  8: "♭13th", 9: "13th", 10: "7th", 11: "major 7th"}

TONE, COLOUR, PASSING, CLASH = "tone", "colour", "passing", "clash"


@dataclass
class SlotNote:
    midi: int
    start: float
    beats: float  # how long it sounds within this slot, in beats
    strength: float  # metric strength where it starts (or 0.6 if held over)
    weight: float
    prev_midi: int | None
    next_midi: int | None

    @property
    def pc(self) -> int:
        return self.midi % 12


@dataclass
class Slot:
    index: int
    start: float
    end: float
    bar: int
    notes: list[SlotNote] = field(default_factory=list)
    phrase_end: bool = False
    last: bool = False

    @property
    def empty(self) -> bool:
        return not self.notes


def build_slots(melody: list[dict], grid: BeatGrid, per_bar: int = 1) -> list[Slot]:
    """Splits the melody into harmony slots on the grid: one per bar by
    default, two for a half-bar harmonic rhythm."""
    if not melody:
        return []
    first_bar = grid.bar_index(melody[0]["start_time"])
    last_bar = grid.bar_index(melody[-1]["end_time"] - 1e-3)
    span = grid.bar_length / per_bar
    slots = []
    for bar in range(first_bar, last_bar + 1):
        for part in range(per_bar):
            start = grid.bar_start(bar) + part * span
            slots.append(Slot(index=len(slots), start=start, end=start + span, bar=bar - first_bar))

    for i, n in enumerate(melody):
        prev_midi = melody[i - 1]["midi_pitch"] if i > 0 else None
        next_midi = melody[i + 1]["midi_pitch"] if i + 1 < len(melody) else None
        for slot in slots:
            overlap = min(n["end_time"], slot.end) - max(n["start_time"], slot.start)
            if overlap <= 0.02:
                continue
            starts_here = slot.start - 0.03 <= n["start_time"] < slot.end
            strength = grid.strength(n["start_time"]) if starts_here else 0.6
            beats = overlap / grid.beat_length
            slot.notes.append(
                SlotNote(
                    midi=n["midi_pitch"],
                    start=max(n["start_time"], slot.start),
                    beats=beats,
                    strength=strength,
                    weight=min(beats, 3.0) * (0.35 + strength),
                    prev_midi=prev_midi,
                    next_midi=next_midi,
                )
            )

    beat = grid.beat_length
    for i, slot in enumerate(slots):
        slot.last = i == len(slots) - 1
        if slot.last:
            slot.phrase_end = True
            continue
        if per_bar == 1 and (slot.bar + 1) % 4 == 0:
            slot.phrase_end = True
        own = [n for n in melody if slot.start <= n["start_time"] < slot.end]
        if own:
            final = own[-1]
            held = final["end_time"] - final["start_time"] >= 1.5 * beat
            later = [n for n in melody if n["start_time"] > final["start_time"]]
            rest_after = not later or later[0]["start_time"] - final["end_time"] >= 0.9 * beat
            if (held or rest_after) and final["end_time"] >= slot.end - 0.6 * beat:
                slot.phrase_end = True
    return slots


def classify(note: SlotNote, chord: Chord) -> str:
    """Whether a melody note is a chord tone, colour (an available
    tension), a passing/neighbour note, or a clash, under this chord."""
    if note.pc in chord.pcs:
        return TONE
    interval = (note.pc - chord.root) % 12
    if interval in _COLOUR[_FAMILY[chord.quality]]:
        return COLOUR
    step_in = note.prev_midi is not None and 0 < abs(note.midi - note.prev_midi) <= 2
    step_out = note.next_midi is not None and 0 < abs(note.next_midi - note.midi) <= 2
    # A passing note runs between two others by step in one direction; it
    # may sit on beat 3, just not on the downbeat. A neighbour or a lone
    # step only gets away with a weak beat.
    through = (
        step_in
        and step_out
        and (note.midi - note.prev_midi) * (note.next_midi - note.midi) > 0
    )
    if through and note.beats <= 1.0 and note.strength < 1.0:
        return PASSING
    if (step_in or step_out) and note.beats <= 0.75 and note.strength <= 0.5:
        return PASSING
    return CLASH


def interval_name(note_pc: int, chord: Chord) -> str:
    return _INTERVAL_NAME.get((note_pc - chord.root) % 12, "non-chord tone")


def colour_credit(note_pc: int, chord: Chord) -> float:
    return _COLOUR[_FAMILY[chord.quality]].get((note_pc - chord.root) % 12, 0.0)


def melody_fit(chord: Chord, slot: Slot) -> float:
    """M: weighted share of the slot's melody the chord supports, in
    roughly [-1.4, 1]. An empty slot (a rest) fits anything equally."""
    total = sum(n.weight for n in slot.notes)
    if total <= 0:
        return 0.0
    score = 0.0
    for n in slot.notes:
        kind = classify(n, chord)
        if kind == CLASH:
            severe = n.strength >= 0.75 or n.beats >= 1.0
            score += n.weight * (-1.4 if severe else -0.8)
        elif kind == TONE:
            # The seventh is a chord tone, but a dissonant one: it earns
            # less than the root, third or fifth, so four-note chords don't
            # win just by having more notes to match.
            seventh = len(chord.pcs) == 4 and (n.pc - chord.root) % 12 in (10, 11)
            score += n.weight * (0.65 if seventh else 1.0)
        elif kind == COLOUR:
            score += n.weight * colour_credit(n.pc, chord)
        elif kind == PASSING:
            # Explained by the line it moves along, so half credit: a chord
            # that keeps the strong beats as its own tones while the tune
            # passes between them is a good fit, not a diluted one.
            score += n.weight * 0.5
    return score / total


def has_strong_clash(chord: Chord, slot: Slot) -> bool:
    """A long or strong-beat melody note that clashes: what makes a chord
    sound wrong rather than adventurous."""
    return any(
        classify(n, chord) == CLASH and (n.strength >= 0.75 and n.beats >= 0.9)
        for n in slot.notes
    )


def key_cost(chord: Chord) -> float:
    """K: 0 for the key's own chords, rising for colour and chromatic ones."""
    return KEY_COST[chord.kind]


def root_motion(prev: Chord | None, chord: Chord) -> float:
    """R: the root movements progressions favour."""
    if prev is None:
        return 0.0
    if prev == chord:
        return 0.0  # holding a chord is judged by `repetition`, not here
    move = (chord.root - prev.root) % 12
    if move == 5:  # down a fifth (up a fourth): the strongest pull
        return 0.35
    if move == 7:  # up a fifth
        return 0.12
    if move in (1, 2, 10, 11):  # by step
        return 0.15
    if move in (3, 4, 8, 9):  # by third: a shared-tone, softer move
        return 0.08
    return 0.0


def cadence(prev: Chord | None, chord: Chord, slot: Slot, key: Key, first: bool) -> float:
    """C: a clear start on home, and proper endings at phrase ends — V→I
    to close, IV→I for the softer 'Amen', or pausing on V to leave the
    phrase open."""
    interval = (chord.root - key.tonic) % 12
    home = interval == 0 and chord.quality in ("maj", "min", "maj7", "m7")
    score = 0.0
    if first and home:
        score += 0.35
    if not slot.phrase_end:
        return score
    if slot.last:
        if home:
            score += 1.0
            if prev is not None and prev.function == "dominant" and (prev.root - key.tonic) % 12 in (7, 11):
                score += 0.6
            elif prev is not None and (prev.root - key.tonic) % 12 == 5:
                score += 0.3
        else:
            score -= 0.4
        return score
    if home and prev is not None and prev.function == "dominant":
        score += 0.4
    elif interval == 7 and chord.function == "dominant":
        score += 0.25  # a half cadence
    return score


def repetition(chords: tuple[Chord, ...], chord: Chord, slot: Slot) -> float:
    """Holding a chord is fine; holding it for ages isn't. Over a rest,
    staying put is the natural choice."""
    if not chords:
        return 0.0
    if slot.empty:
        return 0.3 if chords[-1] == chord else -0.2
    run = 0
    for c in reversed(chords):
        if c != chord:
            break
        run += 1
    return -0.15 * run - 0.3 * max(0, run - 1)
