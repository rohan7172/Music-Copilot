from app.harmoniser import harmonise
from app.harmoniser.prior import load_prior
from app.harmoniser.scoring import CLASH, COLOUR, PASSING, TONE, SlotNote, build_slots, classify, melody_fit
from app.harmoniser.search import pick_three, score_fixed
from app.harmoniser.vocab import Key, parse_roman, vocabulary
from app.timing import BeatGrid
from tests.melodies import (
    FRERE_JACQUES,
    FRERE_JACQUES_OK,
    MINOR_TUNE,
    ODE_TO_JOY,
    ODE_TO_JOY_OK,
    TWINKLE,
    TWINKLE_OK,
    notes,
)

C_MAJOR = Key(0, "major")
GRID = BeatGrid(bpm=100, downbeat=0.0)


def chord(symbol_roman: str):
    return parse_roman(symbol_roman, C_MAJOR)


def note(midi, beats=1.0, strength=1.0, prev=None, nxt=None):
    return SlotNote(midi=midi, start=0, beats=beats, strength=strength, weight=1, prev_midi=prev, next_midi=nxt)


def test_vocabulary_spells_borrowed_chords_with_flats():
    symbols = {c.symbol(C_MAJOR) for c in vocabulary(C_MAJOR)}
    assert {"C", "Dm", "G7", "Fmaj7", "Ab", "Bb", "Fm", "E7"} <= symbols


def test_roman_numerals_parse_into_the_key():
    assert parse_roman("V7/vi", C_MAJOR).symbol(C_MAJOR) == "E7"
    assert parse_roman("♭VI", C_MAJOR).symbol(C_MAJOR) == "Ab"
    assert parse_roman("ii7", C_MAJOR).symbol(C_MAJOR) == "Dm7"
    assert parse_roman("bII", C_MAJOR).kind == "chromatic"
    a_minor = Key(9, "minor")
    assert parse_roman("VII", a_minor).symbol(a_minor) == "G"
    assert parse_roman("V", a_minor).symbol(a_minor) == "E"
    assert parse_roman("nonsense", C_MAJOR) is None


def test_note_classes_under_a_chord():
    c = chord("I")
    assert classify(note(64), c) == TONE  # E in C
    assert classify(note(62, strength=1.0), c) == COLOUR  # D, the 9th
    assert classify(note(65, beats=1, strength=0.75, prev=64, nxt=67), c) == PASSING  # E F G
    assert classify(note(65, beats=2, strength=1.0), c) == CLASH  # a held 4th
    assert classify(note(64), chord("IVmaj7")) == TONE  # E is the 7th of Fmaj7


def test_the_doc_worked_example():
    # E (beat 1, half), D (beat 3, eighth), C (held to the bar's end).
    melody = [
        {"midi_pitch": 64, "start_time": 0.0, "end_time": 1.2, "confidence": 0.8},
        {"midi_pitch": 62, "start_time": 1.2, "end_time": 1.5, "confidence": 0.8},
        {"midi_pitch": 60, "start_time": 1.5, "end_time": 2.4, "confidence": 0.8},
    ]
    slot = build_slots(melody, GRID)[0]
    fits = {s: melody_fit(chord(s), slot) for s in ("I", "vi", "IVmaj7", "V")}
    assert fits["I"] > fits["V"]
    assert fits["vi"] > fits["V"]
    assert fits["IVmaj7"] > fits["V"]


def _agreement(tune, ok):
    result = pick_three(build_slots(notes(tune), GRID), C_MAJOR, load_prior())
    symbols = [c.symbol(C_MAJOR) for c in result["safe"].chords]
    return sum(s in allowed for s, allowed in zip(symbols, ok)) / len(ok), result


def test_safe_matches_musicians_on_the_golden_tunes():
    scores = []
    for tune, ok in ((TWINKLE, TWINKLE_OK), (ODE_TO_JOY, ODE_TO_JOY_OK), (FRERE_JACQUES, FRERE_JACQUES_OK)):
        score, result = _agreement(tune, ok)
        scores.append(score)
        assert result["safe"].chords[-1].symbol(C_MAJOR) == "C"  # comes home
    assert sum(scores) / len(scores) >= 0.75


def test_three_progressions_differ_and_colourful_has_colour():
    result = pick_three(build_slots(notes(TWINKLE), GRID), C_MAJOR, load_prior())
    safe, colourful = result["safe"].chords, result["colourful"].chords
    assert sum(a != b for a, b in zip(safe, colourful)) >= len(safe) / 3
    assert any(c.is_colour for c in colourful)
    surprising = result["surprising"]
    assert surprising is not None
    assert any(c.kind in ("borrowed", "secondary", "chromatic") for c in surprising.chords)


def test_minor_tune_cadences_on_the_harmonic_minor_dominant():
    a_minor = Key(9, "minor")
    result = pick_three(build_slots(notes(MINOR_TUNE), GRID), a_minor, load_prior())
    safe = [c.symbol(a_minor) for c in result["safe"].chords]
    assert safe[-1] == "Am"
    assert safe[-2] in ("E", "E7")


def test_a_given_progression_can_be_scored_like_the_others():
    slots = build_slots(notes(ODE_TO_JOY), GRID)
    good = score_fixed(slots, C_MAJOR, load_prior(), [chord(r) for r in "I V I V I V I I".split()])
    bad = score_fixed(slots, C_MAJOR, load_prior(), [chord(r) for r in "ii vii° iii ii vii° iii ii vii°".split()])
    assert good.score > bad.score


def test_harmonise_returns_reasons_for_every_chord():
    result = harmonise(notes(TWINKLE), GRID, {"tonic": "C", "mode": "major"})
    kinds = [p["kind"] for p in result["progressions"]]
    assert kinds == ["safe", "colourful", "bold"]
    for p in result["progressions"]:
        assert p["character"]
        for c in p["chords"]:
            assert c["reasons"]
            assert c["fit"] in ("fits", "colour", "clash")
    assert result["insight"].startswith("Your tune ends on C")
