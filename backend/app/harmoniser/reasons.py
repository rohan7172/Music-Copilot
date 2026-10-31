"""Why each chord works, in plain words, built from the same score terms
that chose it, so a reason is always true of the choice rather than
written afterwards to justify it."""

from app.harmoniser import scoring
from app.harmoniser.vocab import Chord, Key

_FUNCTION_WORDS = {
    "tonic": "home",
    "predominant": "moving away from home",
    "dominant": "pulling back toward home",
}


def _names(key: Key, pcs: list[int]) -> str:
    unique = list(dict.fromkeys(key.name_of(pc) for pc in pcs))
    if len(unique) == 1:
        return unique[0]
    return ", ".join(unique[:-1]) + " and " + unique[-1]


def _important(slot: scoring.Slot) -> list[scoring.SlotNote]:
    """The notes a listener hears as defining the bar: long or on strong beats."""
    notes = [n for n in slot.notes if n.beats >= 0.9 or n.strength >= 0.75]
    return notes or slot.notes


def chord_reasons(
    chord: Chord,
    slot: scoring.Slot,
    prev: Chord | None,
    key: Key,
    cadence: float,
    voice: str = "your",
) -> list[str]:
    """Up to two short sentences, most telling first. `voice` is whose tune
    it is: "your" for the user's take, "the" for a song's melody."""
    texts = _chord_reasons(chord, slot, prev, key, cadence)
    if voice == "your":
        return texts
    return [t.replace("Your tune", "The tune").replace("Your ", "The melody's ") for t in texts]


def _chord_reasons(chord: Chord, slot: scoring.Slot, prev: Chord | None, key: Key, cadence: float) -> list[str]:
    sym = chord.symbol(key)
    reasons: list[tuple[float, str]] = []

    if slot.empty:
        return [f"Your tune rests here, so {sym} just carries the harmony on."]

    tones, colours, passing, clashes = [], [], [], []
    for n in slot.notes:
        kind = scoring.classify(n, chord)
        {scoring.TONE: tones, scoring.COLOUR: colours, scoring.PASSING: passing, scoring.CLASH: clashes}[
            kind
        ].append(n)

    if cadence > 0 and slot.phrase_end and prev is not None:
        prev_sym = prev.symbol(key)
        if slot.last and chord.function == "tonic" and prev.function == "dominant":
            reasons.append((3.0, f"{prev_sym} → {sym} closes the phrase: the strongest way to come home."))
        elif slot.last and chord.function == "tonic" and (prev.root - key.tonic) % 12 == 5:
            reasons.append((2.6, f"{prev_sym} → {sym} is the soft 'Amen' ending."))
        elif chord.function == "dominant" and not slot.last:
            reasons.append((2.2, f"Pausing on {sym} leaves the phrase open, asking to go on."))

    strong_tones = [n for n in tones if n in _important(slot)]
    if strong_tones:
        names = _names(key, [n.pc for n in strong_tones])
        verb = "is" if len({n.pc for n in strong_tones}) == 1 else "are"
        mood = "settled" if chord.function == "tonic" else "supported"
        reasons.append((2.0 + 0.1 * len(strong_tones), f"Your {names} {verb} in {sym}, so it feels {mood}."))

    long_colour = sorted(colours, key=lambda n: -n.beats)
    if long_colour:
        n = long_colour[0]
        what = scoring.interval_name(n.pc, chord)
        length = "long " if n.beats >= 1.5 else ""
        reasons.append((2.4 if chord.is_colour else 1.4, f"Your {length}{key.name_of(n.pc)} becomes the {what} over {sym}: a richer colour."))

    if passing and len(reasons) < 2:
        reasons.append((0.8, f"The {_names(key, [n.pc for n in passing])} just passes through."))

    if chord.kind == "borrowed":
        reasons.append((2.5, f"{sym} is borrowed from the parallel {'minor' if key.mode == 'major' else 'major'}: a bittersweet shade."))
    elif chord.kind == "secondary":
        target = chord.roman.split("/")[-1]
        reasons.append((2.5, f"{sym} is the dominant of {target}: it leans hard into the next chord."))
    elif chord.kind == "chromatic":
        reasons.append((2.3, f"{sym} steps outside the key for a moment: a bold, unexpected colour."))

    if clashes:
        n = max(clashes, key=lambda x: x.weight)
        reasons.append((2.7, f"Your {key.name_of(n.pc)} rubs against {sym}: a deliberate bit of tension."))

    if not reasons:
        reasons.append((1.0, f"{sym} is {_FUNCTION_WORDS[chord.function]}."))
    reasons.sort(key=lambda r: -r[0])
    return [text for _, text in reasons[:2]]


def fit_label(chord: Chord, slot: scoring.Slot, fit: float) -> str:
    """'fits', 'colour' or 'clash', the three grades the app shows."""
    if scoring.has_strong_clash(chord, slot) or (not slot.empty and fit < 0.15):
        return "clash"
    if chord.is_colour or any(scoring.classify(n, chord) == scoring.COLOUR for n in slot.notes):
        return "colour"
    return "fits"


def character(kind: str, chords: list[Chord], key: Key) -> str:
    """The one-line mood of a whole progression."""
    if kind == "safe":
        return "warm and settled" if all(c.kind == "diatonic" for c in chords) else "settled, lightly coloured"
    borrowed = next((c for c in chords if c.kind == "borrowed"), None)
    secondary = next((c for c in chords if c.kind == "secondary"), None)
    if kind == "colourful":
        if borrowed:
            return f"a bittersweet lift from {borrowed.symbol(key)}"
        if any(c.quality in ("maj7", "m7", "7") for c in chords):
            return "lush sevenths"
        return "brighter and more open"
    turn = next((i for i, c in enumerate(chords) if c.kind in ("borrowed", "secondary", "chromatic")), None)
    if turn is not None:
        return f"an unexpected turn in bar {turn + 1}"
    return "a different road home"


def insight(melody: list[dict], slots: list[scoring.Slot], safe: list[Chord], key: Key, grid) -> str | None:
    """The one thing worth noticing about this tune, shown first."""
    if not melody or not safe:
        return None
    last = melody[-1]
    if last["midi_pitch"] % 12 == key.tonic and len(safe) >= 2:
        home = key.name_of(key.tonic)
        before = safe[-2]
        if before.function == "dominant":
            return (
                f"Your tune ends on {home}, its home note, so "
                f"{before.symbol(key)} right before it makes a strong ending."
            )
        if (before.root - key.tonic) % 12 == 5:
            return (
                f"Your tune ends on {home}, its home note; {before.symbol(key)} before it "
                f"gives the soft 'Amen' ending, and a {key.name_of(key.tonic + 7)} there would close it harder."
            )
    longest = max(melody, key=lambda n: n["end_time"] - n["start_time"])
    beats = (longest["end_time"] - longest["start_time"]) / grid.beat_length
    if beats >= 1.5:
        bar = next((s.index + 1 for s in slots if s.start <= longest["start_time"] < s.end), None)
        name = key.name_of(longest["midi_pitch"])
        if bar:
            return f"Bar {bar} holds a long {name}: any chord with {name} in it will feel stable there."
    return f"Your tune sits in {key.name_of(key.tonic)} {key.mode}: its home note is {key.name_of(key.tonic)}."
