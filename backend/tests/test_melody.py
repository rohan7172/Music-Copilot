import numpy as np

from app.melody import audible_notes, classify_input, detect_melody_key, extract_melody, has_singing
from app.timing import BeatGrid, estimate_grid, grid_from_click
from tests.melodies import C4, E4, G4, MINOR_TUNE, ODE_TO_JOY, TWINKLE, notes


def _note(midi, start, end, confidence=0.8):
    return {"pitch": "", "midi_pitch": midi, "start_time": start, "end_time": end, "confidence": confidence}


def test_single_line_is_a_melody():
    assert classify_input(notes(TWINKLE)) == "melody"


def test_block_chords_are_polyphonic():
    chords = []
    for i in range(8):
        t = i * 0.6
        chords += [_note(48, t, t + 0.55), _note(52, t, t + 0.55), _note(55, t, t + 0.55)]
    assert classify_input(chords) == "polyphonic"


def test_chords_with_drums_are_a_full_mix():
    chords = []
    for i in range(8):
        t = i * 0.6
        chords += [_note(48, t, t + 0.55), _note(52, t, t + 0.55), _note(55, t, t + 0.55)]
    assert classify_input(chords, percussive_share=0.05) == "full_mix"
    assert classify_input(notes(TWINKLE), percussive_share=0.05) == "melody"


def test_dense_texture_is_a_full_mix():
    dense = []
    for i in range(8):
        t = i * 0.6
        dense += [_note(p, t, t + 0.6) for p in (36, 48, 52, 55, 60, 64, 72)]
    assert classify_input(dense) == "full_mix"


def test_melody_keeps_the_top_line():
    played = [
        _note(48, 0.0, 2.0),  # a held low note under the tune
        _note(C4, 0.0, 0.5),
        _note(E4, 0.5, 1.0),
        _note(G4, 1.0, 1.5),
    ]
    line = extract_melody(played)
    assert [n["midi_pitch"] for n in line] == [C4, E4, G4, 48]
    assert line[-1]["start_time"] == 1.5  # the low note only shows once the tune stops


def test_melody_keeps_repeated_notes_but_rejoins_fragments():
    played = [
        _note(C4, 0.0, 0.5), _note(C4, 0.5, 1.0),  # sung twice, abutting
        _note(E4, 1.0, 1.04),  # a blip
        _note(G4, 1.1, 1.5), _note(G4, 1.5, 1.65),  # one note split in two
    ]
    line = extract_melody(played)
    assert [(n["midi_pitch"], n["start_time"], n["end_time"]) for n in line] == [
        (C4, 0.0, 0.5),
        (C4, 0.5, 1.0),
        (G4, 1.1, 1.65),
    ]


def test_grid_strength_ranks_beats():
    grid = BeatGrid(bpm=120, downbeat=0.0)
    assert grid.strength(0.0) == 1.0
    assert grid.strength(1.0) == 0.75  # beat 3 of 4
    assert grid.strength(0.5) == 0.5  # beat 2
    assert grid.strength(0.25) == 0.3  # an off-beat eighth
    assert grid.bar_index(2.1) == 1


def test_click_grid_is_exact():
    grid = grid_from_click(90, 0.4)
    assert not grid.guessed
    assert grid.downbeat == 0.4


def test_tempo_and_downbeat_are_estimated_from_the_melody():
    for tune in (TWINKLE, ODE_TO_JOY):
        grid = estimate_grid(notes(tune, bpm=100, start=0.25))
        assert grid.guessed
        assert abs(grid.bpm - 100) < 4
        bar = grid.bar_length
        offset = (grid.downbeat - 0.25) % bar
        assert min(offset, bar - offset) < 0.1


def test_key_of_a_major_tune():
    melody = notes(TWINKLE)
    key = detect_melody_key(melody, BeatGrid(bpm=100, downbeat=0.0))
    assert key["name"] == "C major"
    assert "runner_up" in key


def test_key_of_a_minor_tune():
    key = detect_melody_key(notes(MINOR_TUNE), BeatGrid(bpm=100, downbeat=0.0))
    assert key["name"] == "A minor"


def _stem(loud_from: float, loud_to: float, seconds: float = 4.0, rate: int = 1000, level: float = 0.5):
    """Silence, except a tone-loud stretch from `loud_from` to `loud_to`."""
    stem = np.full(int(seconds * rate), 1e-4)
    stem[int(loud_from * rate) : int(loud_to * rate)] = level
    return stem


def test_audible_notes_drop_a_confident_note_the_stem_has_no_sound_for():
    # Basic Pitch hears pitch at any volume, so a separator's faint residue
    # comes back as a confident note: only loudness gives it away.
    leak, sung = _note(60, 0.5, 1.0, confidence=0.9), _note(64, 2.0, 3.0, confidence=0.5)
    kept = audible_notes([leak, sung], _stem(2.0, 3.0), mix_level=0.5, rate=1000)
    assert kept == [sung]


def test_audible_notes_are_measured_against_the_mix():
    note = _note(60, 2.0, 3.0)
    stem = _stem(2.0, 3.0, level=0.02)
    assert audible_notes([note], stem, mix_level=0.1, rate=1000) == [note]  # a fifth of the mix
    assert audible_notes([note], stem, mix_level=0.5, rate=1000) == []  # a 25th of it


def test_audible_notes_survive_a_note_past_the_end_of_the_audio():
    assert audible_notes([_note(60, 9.0, 10.0)], _stem(0, 1), mix_level=0.5, rate=1000) == []


def test_a_few_notes_of_residue_are_not_singing():
    assert not has_singing([])
    assert not has_singing([_note(60, t, t + 0.3) for t in range(6)])  # 1.8 s
    assert has_singing([_note(60, t, t + 0.5) for t in range(10)])  # 5 s
