import time

import numpy as np

from app.harmoniser.vocab import Key
from app.songs import decode, jobs
from app.songs.btc import NUM_CLASSES, NO_CHORD, class_chord
from app.songs.pipeline import bass_per_beat, describe_recognised, grid_from_beats
from tests.melodies import TWINKLE, notes

C_MAJOR = Key(0, "major")


def _class(root: int, quality_index: int = 1) -> int:
    """BTC class index: quality 1 is major, 0 minor, 9 dominant seventh."""
    return root * 14 + quality_index


def _state(root, quality):
    return decode.STATES.index((root, quality))


def _emissions(per_beat: list[int], noise: float = 0.1, flip: dict | None = None) -> np.ndarray:
    """Beat-level state probabilities: mostly the given state, a little noise;
    `flip` makes some beats lean (wrongly) to another state."""
    out = np.full((len(per_beat), len(decode.STATES)), noise / len(decode.STATES))
    for i, s in enumerate(per_beat):
        out[i, s] += 1 - noise
    for i, s in (flip or {}).items():
        out[i] = noise / len(decode.STATES)
        out[i, s] += 0.5
        out[i, per_beat[i]] += 0.4
    return out


def test_btc_classes_collapse_to_harmoniser_qualities():
    assert class_chord(_class(0)) == (0, "maj")
    assert class_chord(_class(9, 0)) == (9, "min")
    assert class_chord(_class(7, 9)) == (7, "7")
    assert class_chord(NO_CHORD) is None


def test_beat_emissions_average_frames_within_each_beat():
    probs = np.zeros((40, NUM_CLASSES))
    probs[:20, _class(0)] = 1.0  # C for the first 2 s
    probs[20:, _class(7)] = 1.0  # G after
    em = decode.beat_emissions(probs, 0.1, np.array([0.0, 1.0, 2.0, 3.0]), 4.0)
    assert em[0].argmax() == _state(0, "maj")
    assert em[3].argmax() == _state(7, "maj")


def test_key_from_a_I_IV_V_song():
    c, f, g = _state(0, "maj"), _state(5, "maj"), _state(7, "maj")
    key = decode.estimate_key(_emissions([c, c, f, f, g, g, c, c] * 2))
    assert (key.tonic, key.mode) == (0, "major")


def test_decoder_holds_through_a_noisy_beat_and_changes_on_downbeats():
    c, g = _state(0, "maj"), _state(7, "maj")
    per_beat = [c] * 8 + [g] * 8
    # Beat 5 (not a downbeat) leans to G for no reason: one noisy beat.
    em = _emissions(per_beat, flip={5: g})
    downbeats = [i % 4 == 0 for i in range(16)]
    path, conf = decode.decode(em, downbeats, C_MAJOR)
    assert path == per_beat
    assert all(0 <= x <= 1 for x in conf)


def test_the_bass_settles_an_ambiguous_chord():
    am, c = _state(9, "min"), _state(0, "maj")
    em = np.full((4, len(decode.STATES)), 0.01)
    em[:, am] = 0.45
    em[:, c] = 0.44  # nearly a tie between Am and C...
    path, _ = decode.decode(em, [True, False, False, False], C_MAJOR, bass_pcs=[0, 0, 0, 0])
    assert path == [c] * 4  # ...but C is in the bass


def test_segments_merge_and_drop_no_chord():
    c, g, n = _state(0, "maj"), _state(7, "maj"), len(decode.STATES) - 1
    segs = decode.segments([n, c, c, g], [0.9, 0.8, 0.6, 0.7], np.array([0.0, 1.0, 2.0, 3.0]), 4.0)
    assert [(s["state"], s["start"], s["end"]) for s in segs] == [((0, "maj"), 1.0, 3.0), ((7, "maj"), 3.0, 4.0)]
    assert abs(segs[0]["confidence"] - 0.7) < 1e-9


def test_grid_from_detected_beats():
    beats = np.arange(0.5, 20, 0.5)  # 120 bpm
    downbeats = beats[::4]
    grid = grid_from_beats(beats, downbeats)
    assert abs(grid.bpm - 120) < 0.5
    assert grid.meter == 4
    assert grid.downbeat == 0.5
    assert not grid.guessed


def test_bass_note_per_beat():
    bass = [
        {"midi_pitch": 36, "start_time": 0.0, "end_time": 0.9},
        {"midi_pitch": 43, "start_time": 1.0, "end_time": 1.9},
    ]
    assert bass_per_beat(bass, np.array([0.0, 1.0, 2.0]), 3.0) == [0, 7, None]


def test_recognised_chords_become_an_original_card():
    grid = grid_from_beats(np.arange(0, 30, 0.6), np.arange(0, 30, 2.4))
    segs = [
        {"state": (0, "maj"), "start": 0.0, "end": 2.4, "confidence": 0.9},
        {"state": (5, "maj"), "start": 2.4, "end": 4.8, "confidence": 0.3},
    ]
    card = describe_recognised(segs, notes(TWINKLE), grid, C_MAJOR)
    assert card["kind"] == "original"
    assert [c["symbol"] for c in card["chords"]] == ["C", "F"]
    assert card["chords"][1]["roman"] == "IV"
    assert card["chords"][0]["reasons"][0].startswith("Clearly heard")
    assert card["chords"][1]["reasons"][0].startswith("A best guess")
    assert any("melody's" in r for r in card["chords"][0]["reasons"])


def test_jobs_report_progress_then_a_result():
    def work(progress):
        progress("Thinking", 0.5)
        return {"answer": 42}

    job_id = jobs.start(work)
    for _ in range(100):
        job = jobs.get(job_id)
        if job["status"] == "done":
            break
        time.sleep(0.01)
    assert job["status"] == "done"
    assert job["result"] == {"answer": 42}
    assert jobs.get("nope") is None


def test_a_failing_job_says_so():
    def work(progress):
        raise ValueError("no beat")

    job_id = jobs.start(work)
    for _ in range(100):
        if jobs.get(job_id)["status"] != "running":
            break
        time.sleep(0.01)
    assert jobs.get(job_id) == {**jobs.get(job_id), "status": "failed", "error": "no beat"}
