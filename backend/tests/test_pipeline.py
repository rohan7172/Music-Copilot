import io
import wave

from fastapi.testclient import TestClient

from app import synth
from app.pipeline import analyze_notes, suggest
from app.timing import BeatGrid
from tests.melodies import TWINKLE, notes


def test_a_melody_take_gets_grid_key_and_three_progressions():
    result = analyze_notes(notes(TWINKLE, bpm=100, start=0.3), use_llm=False)
    assert result["route"] == "melody"
    assert result["route_note"] is None
    assert result["grid"]["guessed"]
    assert abs(result["grid"]["bpm"] - 100) < 4
    assert result["key"]["name"] == "C major"
    assert [p["kind"] for p in result["progressions"]] == ["safe", "colourful", "bold"]
    assert result["insight"]


def test_a_click_gives_an_exact_grid():
    result = analyze_notes(notes(TWINKLE, bpm=96, start=0.5), bpm=96, first_beat=0.5, use_llm=False)
    assert not result["grid"]["guessed"]
    assert result["grid"]["bpm"] == 96
    first_chord = result["progressions"][0]["chords"][0]
    assert first_chord["start_time"] == 0.5


def test_suggest_honours_a_key_override_and_half_bars():
    melody = notes(TWINKLE)
    grid = BeatGrid(bpm=100, downbeat=0.0)
    plain = suggest(melody, grid, use_llm=False)
    halves = suggest(melody, grid, key={"tonic": "C", "mode": "major"}, per_bar=2, use_llm=False)
    assert len(halves["progressions"][0]["chords"]) == 2 * len(plain["progressions"][0]["chords"])


def test_backing_renders_a_wav_of_the_right_length():
    wav = synth.render(
        [{"start_time": 0, "end_time": 1.0, "pitch_classes": [0, 4, 7]},
         {"start_time": 1.0, "end_time": 2.0, "pitch_classes": [7, 11, 2, 5]}],
        duration=2.0,
    )
    with wave.open(io.BytesIO(wav)) as w:
        assert w.getframerate() == synth.SAMPLE_RATE
        assert abs(w.getnframes() / w.getframerate() - 2.18) < 0.05


def test_voicing_puts_the_root_in_the_bass():
    bass, upper = synth.voicing([7, 11, 2, 5])  # G7
    assert bass % 12 == 7
    assert all(57 <= m < 69 for m in upper)


def test_harmonise_and_backing_endpoints():
    from app.main import app

    client = TestClient(app)  # no lifespan: these endpoints don't need Basic Pitch
    melody = notes(TWINKLE)
    response = client.post(
        "/harmonise",
        json={"melody": melody, "grid": {"bpm": 100, "downbeat": 0.0}, "use_llm": False},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["key"]["name"] == "C major"
    safe = body["progressions"][0]
    wav = client.post("/backing", json={"chords": safe["chords"], "duration": 20})
    assert wav.status_code == 200
    assert wav.headers["content-type"] == "audio/wav"
    assert client.post("/harmonise", json={"melody": melody}).status_code == 400
