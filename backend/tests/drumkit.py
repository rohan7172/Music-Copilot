"""A tiny synthesised drum kit and backing band, for drum-recognition tests.

kick:  a sine that drops from 110 to 50 Hz and dies away in ~0.3 s
snare: a 190 Hz body plus a burst of noise, rolled off above ~5 kHz
hat:   a short burst of high-passed noise (~50 ms)
"""

import numpy as np
from scipy.signal import butter, sosfilt

SR = 22050
_rng = np.random.default_rng(7)


def _kick() -> np.ndarray:
    t = np.arange(int(0.35 * SR)) / SR
    freq = 50 + 60 * np.exp(-t * 30)
    return 0.9 * np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 12)


def _snare() -> np.ndarray:
    t = np.arange(int(0.25 * SR)) / SR
    noise = sosfilt(butter(2, [300 / (SR / 2), 5000 / (SR / 2)], btype="band", output="sos"), _rng.standard_normal(len(t)))
    return (0.5 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) + 0.6 * noise * np.exp(-t * 18))


def _hat() -> np.ndarray:
    t = np.arange(int(0.06 * SR)) / SR
    noise = sosfilt(butter(4, 7000 / (SR / 2), btype="high", output="sos"), _rng.standard_normal(len(t)))
    return 0.35 * noise * np.exp(-t * 70)


SOUNDS = {"kick": _kick(), "snare": _snare(), "hat": _hat()}

# Eighth-note steps per bar for each piece.
ROCK = {"kick": [0, 4], "snare": [2, 6], "hat": [0, 1, 2, 3, 4, 5, 6, 7]}
WALTZ = {"kick": [0], "snare": [2, 4], "hat": [0, 2, 4]}


def render(pattern: dict, bpm: float, bars: int, meter: int = 4, start: float = 0.5) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(drum audio, beat times, downbeat times) for a repeating pattern."""
    beat = 60.0 / bpm
    total = start + bars * meter * beat + 1.0
    y = np.zeros(int(total * SR))
    for bar in range(bars):
        for piece, steps in pattern.items():
            for step in steps:
                t = start + (bar * meter + step / 2) * beat
                i = int(t * SR)
                sound = SOUNDS[piece]
                y[i : i + len(sound)] += sound[: len(y) - i]
    beats = start + np.arange(bars * meter + 1) * beat
    return y, beats, beats[::meter]


def band(seconds: float, level: float = 0.25) -> np.ndarray:
    """A sustained 'band' to mix the drums into: a chord pad and a bass note."""
    t = np.arange(int(seconds * SR)) / SR
    pad = sum(np.sin(2 * np.pi * f * t) for f in (261.6, 329.6, 392.0)) / 3
    bass = np.sin(2 * np.pi * 65.4 * t)
    return level * (0.7 * pad + 0.3 * bass)
