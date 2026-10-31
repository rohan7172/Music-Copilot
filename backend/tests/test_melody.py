from app.melody import classify_input, detect_melody_key, extract_melody
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
