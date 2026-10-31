"""Finding where the music starts, and the grid fixes that depend on it."""

import numpy as np

from app.harmoniser.scoring import build_slots
from app.melody import extract_melody
from app.onset import music_start_samples, trim_notes
from app.pipeline import analyze_notes
from app.timing import estimate_grid
from tests.melodies import C4, D4, E4, G4, ODE_TO_JOY, TWINKLE, notes

SR = 22050
rng = np.random.default_rng(0)


def _take(lead: float, music: float = 4.0, hum: bool = True) -> np.ndarray:
    """Room noise (with mains hum) for `lead` seconds, then a sung-ish tone."""
    n = int((lead + music) * SR)
    t = np.arange(n) / SR
    y = 0.003 * rng.standard_normal(n)
    if hum:
        y += 0.004 * np.sin(2 * np.pi * 50 * t)
    tone = 0.3 * np.sin(2 * np.pi * 262 * t) * (t >= lead)
    return y + tone


def test_finds_a_silent_lead_in():
    for lead in (1.0, 2.5, 4.0):
        start = music_start_samples(_take(lead), SR)
        assert lead - 0.15 <= start <= lead + 0.05


def test_hum_alone_is_not_music():
    """A loud mains hum (-34 dBFS) switching on is not the music starting:
    it sits below the high-pass."""
    y = _take(3.0)
    y[int(3.0 * SR):] = 0.003 * rng.standard_normal(len(y) - int(3.0 * SR)) + 0.02 * np.sin(
        2 * np.pi * 50 * np.arange(len(y) - int(3.0 * SR)) / SR
    )
    assert music_start_samples(y, SR) == 0.0


def test_no_lead_in_means_no_trim():
    assert music_start_samples(_take(0.0), SR) == 0.0
    assert music_start_samples(_take(0.1), SR) == 0.0


def test_a_click_is_not_the_start():
    y = _take(3.0)
    y[int(1.0 * SR):int(1.0 * SR) + 200] += 0.8  # a tap on the phone
    assert music_start_samples(y, SR) > 2.8


def test_trim_drops_lead_in_ghosts():
    ghost = {"pitch": "G1", "midi_pitch": 31, "start_time": 1.3, "end_time": 1.6, "confidence": 0.35}
    sung = notes([(C4, 1), (E4, 1), (G4, 2)], start=3.0)
    kept = trim_notes([ghost] + sung, 2.95)
    assert kept == sung


def test_low_hum_never_becomes_the_melody():
    ghost = {"pitch": "G1", "midi_pitch": 31, "start_time": 0.0, "end_time": 0.3, "confidence": 0.4}
    melody = extract_melody([ghost] + notes([(C4, 1), (D4, 1)], start=1.0))
    assert all(n["midi_pitch"] >= 40 for n in melody)


def test_chords_start_with_the_music_not_the_silence():
    ghost = {"pitch": "G1", "midi_pitch": 31, "start_time": 0.6, "end_time": 0.9, "confidence": 0.38}
    sung = notes(ODE_TO_JOY, bpm=100, start=3.0)
    result = analyze_notes([ghost] + sung, use_llm=False, music_start=2.9)
    first = result["progressions"][0]["chords"][0]
    assert abs(first["start_time"] - 3.0) < 0.15
    assert result["music_start"] == 2.9


def test_tempo_is_refined_so_the_grid_does_not_drift():
    """The tempogram is often a couple of percent out; over a whole tune
    that slides the bars off the melody. The refined grid stays on it."""
    for tune in (TWINKLE, ODE_TO_JOY):
        melody = notes(tune, bpm=100, start=3.0)
        grid = estimate_grid(melody)
        assert abs(grid.bpm - 100) < 0.6
        last = melody[-1]["start_time"]
        drift = (last - grid.downbeat) / grid.beat_length
        assert abs(drift - round(drift)) < 0.1


WALTZ = [  # 3/4: long note on each downbeat, phrase every 4 bars
    (G4, 2), (E4, 1), (C4, 2), (E4, 1), (G4, 2), (E4, 1), (D4, 3),
    (G4, 2), (E4, 1), (C4, 2), (D4, 1), (E4, 2), (D4, 1), (C4, 3),
] * 2


def test_waltz_time_is_detected():
    assert estimate_grid(notes(WALTZ, bpm=120, start=1.0)).meter == 3
    assert estimate_grid(notes(ODE_TO_JOY, bpm=100, start=1.0)).meter == 4
    assert estimate_grid(notes(TWINKLE, bpm=100, start=1.0)).meter == 4


def test_a_note_ringing_past_the_last_bar_line_adds_no_bar():
    melody = notes(ODE_TO_JOY, bpm=100, start=0.0)
    melody[-1]["end_time"] += 0.12  # Basic Pitch's release tail
    grid = estimate_grid(melody, 4)
    slots = build_slots(melody, grid)
    assert len(slots) == 8


# --- Fixes on top of the patch ------------------------------------------------


def test_a_short_last_note_keeps_its_bar():
    melody = notes(ODE_TO_JOY, bpm=100, start=0.0)
    beat = 0.6
    bar_end = 8 * 4 * beat  # where bar 8 ends
    melody.append({"pitch": "", "midi_pitch": C4, "start_time": bar_end + 0.02, "end_time": bar_end + 0.12, "confidence": 0.8})
    slots = build_slots(melody, estimate_grid(melody, 4))
    assert len(slots) == 9  # the short note just past the bar line gets bar 9


def test_finds_a_short_lead_in_at_the_start_of_a_long_clip():
    """A 2 s lead-in is only 2% of a 90 s song: a percentile-based background
    level would land inside the music and miss it."""
    sr = 44100
    n = 90 * sr
    t = np.arange(n) / sr
    y = 0.003 * rng.standard_normal(n) + 0.3 * np.sin(2 * np.pi * 262 * t) * (t >= 2.0)
    assert 1.85 <= music_start_samples(y, sr) <= 2.05


def test_windowed_energy_matches_the_direct_calculation():
    from app.onset import _FRAME, _HOP, _frame_db

    y = rng.standard_normal(20000)
    direct = [
        10 * np.log10(np.mean(y[i : i + _FRAME] ** 2) + 1e-20)
        for i in range(0, len(y) - _FRAME + 1, _HOP)
    ]
    assert np.allclose(_frame_db(y), direct, atol=1e-6)


def test_analyze_song_reuses_notes_instead_of_transcribing_the_mix(tmp_path, monkeypatch):
    import soundfile as sf

    from app.songs import models
    from app.songs.btc import NUM_CLASSES
    from app.songs.pipeline import analyze_song

    sr = 44100
    t = np.arange(8 * sr) / sr
    path = tmp_path / "chords.wav"
    sf.write(path, 0.3 * np.sin(2 * np.pi * 262 * t), sr)

    def fake_probs(audio):
        p = np.full((int(len(audio) / 2048) + 1, NUM_CLASSES), 1e-3)
        p[:, 1] = 1.0  # C major throughout
        return p

    monkeypatch.setattr(models, "beats", lambda mono, rate: (np.arange(0, 8, 0.5), np.arange(0, 8, 2.0)))
    monkeypatch.setattr(models, "chord_probabilities", fake_probs)
    calls = []

    def transcribe(p):
        calls.append(p)
        return []

    given = notes(TWINKLE[:8], bpm=120)
    result = analyze_song(str(path), transcribe, "polyphonic", use_llm=False, notes=given, start=0.0)
    assert calls == []  # the mix wasn't transcribed again
    assert result["progressions"][0]["chords"][0]["symbol"] == "C"
    assert result["melody"]
