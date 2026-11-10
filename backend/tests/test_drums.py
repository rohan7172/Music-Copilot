"""Drum recognition on synthesised kits: presence, kit pieces, groove."""

import numpy as np

from app.songs import drums
from tests.drumkit import ROCK, SR, WALTZ, band, render

DANCE = {"kick": [0, 2, 4, 6], "snare": [2, 6], "hat": [1, 3, 5, 7]}


def _analyse(pattern, meter=4, bpm=120, bars=12, drum_level=1.0, band_level=0.25):
    y, beats, downbeats = render(pattern, bpm, bars, meter)
    stem = y * drum_level
    mix = stem + band(len(y) / SR, band_level)
    return drums.analyse(stem, mix, SR, beats, downbeats, meter)


def test_a_rock_beat_is_recognised_piece_by_piece():
    role, notes = _analyse(ROCK)
    assert role["summary"].startswith("Kick on 1 and 3, snare on 2 and 4 (a backbeat), hi-hat on every eighth note")
    assert "rock and pop" in role["summary"]
    names = {n["pitch"] for n in notes}
    assert names == {"Kick", "Snare", "Hi-hat"}
    kicks = [n for n in notes if n["pitch"] == "Kick"]
    assert len(kicks) == 2 * 12  # two a bar, none of the snares mistaken for kicks


def test_four_on_the_floor_with_off_beat_hats():
    role, _ = _analyse(DANCE)
    assert "four on the floor" in role["summary"]
    assert "off-beats" in role["summary"]
    assert "dance groove" in role["summary"]


def test_a_waltz_is_read_in_three():
    role, _ = _analyse(WALTZ, meter=3)
    assert role["summary"].startswith("Kick on 1, snare on 2 and 3, hi-hat on every beat")
    assert "waltz" in role["summary"]


def test_leakage_in_a_drumless_song_is_not_drums():
    """Demucs's drum stem for a drumless song is quiet leakage: it must not
    become hundreds of hits (the bug this module replaces)."""
    role, notes = _analyse(ROCK, drum_level=10 ** (-35 / 20), band_level=0.5)
    assert role == drums.NO_DRUMS
    assert notes == []


def test_kick_and_hat_together_are_both_heard():
    y, beats, downbeats = render({"kick": [0, 2, 4, 6], "hat": [0, 2, 4, 6]}, 100, 6)
    strokes = drums.detect_hits(y, y + band(len(y) / SR), SR)
    together = [s for s in strokes if s["pieces"] == ["hat", "kick"]]
    assert len(together) >= 0.8 * len(strokes)


def test_bar_positions_follow_the_real_beats_not_an_average():
    # A tempo that speeds up: beat gaps shrink from 0.6 s to 0.4 s.
    gaps = np.linspace(0.6, 0.4, 40)
    beats = np.concatenate([[0.0], np.cumsum(gaps)])
    downbeats = beats[::4]
    t = beats[30] + 0.5 * (beats[31] - beats[30])  # the & of beat 3 in bar 8
    index, frac = drums.bar_position(t, beats, downbeats)
    assert index == 2 and abs(frac - 0.5) < 1e-9


def test_off_beat_leakage_at_a_plausible_level_is_not_drums():
    """Leakage can be as loud, relative to the mix, as a real drummer under
    a loud vocal; what gives it away is that it isn't on the beat."""
    rng = np.random.default_rng(3)
    _, beats, downbeats = render(ROCK, 120, 12)
    y = np.zeros(int((beats[-1] + 1.0) * SR))
    from tests.drumkit import SOUNDS

    for t in np.sort(rng.uniform(0.5, beats[-1], 40)):  # random, unaligned hits
        i = int(t * SR)
        sound = SOUNDS["snare"]
        y[i : i + len(sound)] += 0.4 * sound[: len(y) - i]
    mix = y + band(len(y) / SR)
    assert drums.analyse(y, mix, SR, beats, downbeats, 4)[0] == drums.NO_DRUMS


def test_quiet_drums_under_a_loud_band_still_count():
    role, notes = _analyse(ROCK, drum_level=0.25, band_level=0.6)
    assert role != drums.NO_DRUMS
    assert "snare on 2 and 4" in role["summary"]

