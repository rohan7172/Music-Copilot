import io
import wave

import pytest
from fastapi.testclient import TestClient

from app import synth
from app.harmoniser.voices import HELD, HIGH, LOW, harmonies, harmony_line
from app.pipeline import suggest
from app.timing import BeatGrid
from tests.melodies import MINOR_TUNE, ODE_TO_JOY, TWINKLE, notes

GRID = BeatGrid(bpm=100, downbeat=0.0)


def _setup(tune):
    melody = notes(tune)
    result = suggest(melody, GRID, use_llm=False)
    return melody, result["progressions"][0]["chords"], result["key"]


def _chord_at(chords, t):
    return next(c for c in chords if c["start_time"] <= t < c["end_time"])


@pytest.mark.parametrize("tune", [TWINKLE, ODE_TO_JOY, MINOR_TUNE])
@pytest.mark.parametrize("style", [HIGH, LOW])
def test_a_harmony_shadows_the_tune_without_clashing(tune, style):
    melody, chords, key = _setup(tune)
    line = harmony_line(melody, chords, key, style, GRID)
    assert len(line) == len(melody)  # note for note, in the tune's rhythm
    for h, m in zip(line, melody):
        gap = h["midi_pitch"] - m["midi_pitch"]
        assert (gap > 0) == style.above
        # Never a unison, a second or a seventh against the tune.
        assert abs(gap) % 12 not in (0, 1, 2, 10, 11)


@pytest.mark.parametrize("tune", [TWINKLE, ODE_TO_JOY, MINOR_TUNE])
def test_strong_beats_land_on_chord_tones(tune):
    melody, chords, key = _setup(tune)
    for style in (HIGH, LOW, HELD):
        line = harmony_line(melody, chords, key, style, GRID)
        on_beat_one = [n for n in line if GRID.strength(n["start_time"]) == 1.0]
        inside = [n for n in on_beat_one if n["midi_pitch"] % 12 in _chord_at(chords, n["start_time"])["pitch_classes"]]
        assert len(inside) >= 0.8 * len(on_beat_one)


def test_mostly_thirds_for_the_duet_styles():
    melody, chords, key = _setup(ODE_TO_JOY)
    high = harmony_line(melody, chords, key, HIGH, GRID)
    thirds = sum(abs(h["midi_pitch"] - m["midi_pitch"]) in (3, 4) for h, m in zip(high, melody))
    assert thirds >= 0.6 * len(melody)


def test_the_line_is_singable():
    melody, chords, key = _setup(TWINKLE)
    for style in (HIGH, LOW, HELD):
        line = harmony_line(melody, chords, key, style, GRID)
        leaps = [abs(b["midi_pitch"] - a["midi_pitch"]) for a, b in zip(line, line[1:])]
        assert max(leaps) <= 9


def test_the_held_line_holds():
    melody, chords, key = _setup(TWINKLE)
    held = harmony_line(melody, chords, key, HELD, GRID)
    assert len(held) < len(melody) / 2
    assert held[0]["start_time"] == melody[0]["start_time"]
    assert held[-1]["end_time"] == melody[-1]["end_time"]


def test_three_options_each_explained():
    melody, chords, key = _setup(TWINKLE)
    options = harmonies(melody, chords, key, GRID)
    assert [o["id"] for o in options] == ["high", "low", "held"]
    for o in options:
        assert o["name"] and o["character"] and o["detail"] and o["range"]
        assert {"pitch", "midi_pitch", "start_time", "end_time", "confidence"} <= set(o["notes"][0])
    assert harmonies([], chords, key) == []
    assert harmonies(melody, chords, None) == []


def test_a_line_renders_to_a_wav_of_the_right_length():
    wav = synth.render_line(
        [{"midi_pitch": 64, "start_time": 0.0, "end_time": 0.8}, {"midi_pitch": 67, "start_time": 0.8, "end_time": 1.5}],
        duration=2.0,
    )
    with wave.open(io.BytesIO(wav)) as w:
        assert abs(w.getnframes() / w.getframerate() - 2.0) < 0.01


def test_voices_and_line_endpoints():
    from app.main import app

    client = TestClient(app)
    melody, chords, key = _setup(TWINKLE)
    body = client.post(
        "/voices",
        json={"melody": melody, "chords": chords, "key": key, "grid": {"bpm": 100, "downbeat": 0.0}},
    ).json()
    assert len(body["harmonies"]) == 3
    wav = client.post("/line", json={"notes": body["harmonies"][0]["notes"], "duration": 20})
    assert wav.status_code == 200
    assert wav.headers["content-type"] == "audio/wav"
    assert client.post("/line", json={"notes": []}).status_code == 400
    assert client.post("/voices", json={"melody": melody, "grid": {"bpm": "x"}}).status_code == 400
