"""Renders a progression as a soft backing pad, to play under the user's
own recording.

Additive synthesis, the same technique as scripts/generate_splash_chime.py:
each chord is three or four sine-based voices in close position around
middle C plus a bass root an octave or two down, shaped with a soft
attack and a release that overlaps the next chord so changes don't click.
"""

import io
import wave

import numpy as np

SAMPLE_RATE = 22050
_ATTACK = 0.05
_RELEASE = 0.18
_PARTIALS = ((1.0, 1.0), (2.0, 0.35), (3.0, 0.12))  # (harmonic, level): a warm, organ-like tone


def _hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def voicing(pitch_classes: list[int]) -> tuple[int, list[int]]:
    """(bass MIDI note, upper MIDI notes) for a chord whose first pitch
    class is its root: bass in the octave above E2, upper voices packed
    into the octave from A3."""
    root = pitch_classes[0]
    bass = 36 + root
    if bass < 40:
        bass += 12
    upper = sorted(57 + ((pc - 57) % 12) for pc in pitch_classes)
    return bass, upper


def _tone(midi: int, length: float, level: float, pluck: bool = False) -> np.ndarray:
    n = int(length * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    wave_ = sum(amp * np.sin(2 * np.pi * _hz(midi) * h * t) for h, amp in _PARTIALS)
    envelope = np.minimum(1.0, t / _ATTACK)
    if pluck:
        envelope *= np.exp(-t * 1.4)  # a bass that blooms then fades
    release = int(_RELEASE * SAMPLE_RATE)
    if n > release:
        envelope[-release:] *= np.linspace(1.0, 0.0, release)
    return level * envelope * wave_


def render(chords: list[dict], duration: float) -> bytes:
    """A 16-bit mono WAV of the progression, `duration` seconds long.
    Each chord dict needs start_time, end_time and pitch_classes (root
    first), as the harmoniser returns them."""
    total = int((duration + _RELEASE) * SAMPLE_RATE) + 1
    mix = np.zeros(total)
    for chord in chords:
        start = max(0.0, float(chord["start_time"]))
        end = min(duration, float(chord["end_time"]))
        if end <= start:
            continue
        length = end - start + _RELEASE
        bass, upper = voicing(list(chord["pitch_classes"]))
        layer = _tone(bass, length, 0.32, pluck=True)
        for midi in upper:
            layer = layer + _tone(midi, length, 0.16)
        i = int(start * SAMPLE_RATE)
        span = min(len(layer), total - i)
        mix[i : i + span] += layer[:span]

    peak = np.abs(mix).max()
    if peak > 0:
        mix *= 0.55 / peak  # leave headroom: it plays under the user's voice
    pcm = (mix * 32767).astype(np.int16)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm.tobytes())
    return buffer.getvalue()
