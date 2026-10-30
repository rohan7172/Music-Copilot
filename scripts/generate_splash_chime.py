#!/usr/bin/env python3
"""Synthesizes the splash screen's chime: a short, soft sine-wave arpeggio.

No audio assets existed in the project, so this generates one deterministically
rather than sourcing a clip. Run with `python3 scripts/generate_splash_chime.py`
to regenerate `app/assets/sounds/chime.wav` (e.g. after changing the notes).
"""

import math
import struct
import wave

SAMPLE_RATE = 44100
# A gentle three-note rise (C5, E5, G5) — "one little pulse that plays a
# certain note, two notes or three notes" per the splash screen brief.
NOTES_HZ = [523.25, 659.25, 783.99]
NOTE_DURATION = 0.22
GAP = 0.05
FADE = 0.02  # seconds of fade in/out per note, so each tone has no click.


def note_samples(freq: float) -> list[float]:
    n = int(SAMPLE_RATE * NOTE_DURATION)
    fade_n = int(SAMPLE_RATE * FADE)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        envelope = 1.0
        if i < fade_n:
            envelope = i / fade_n
        elif i > n - fade_n:
            envelope = (n - i) / fade_n
        # A touch of the third harmonic for warmth, not a bare sine.
        value = math.sin(2 * math.pi * freq * t) + 0.08 * math.sin(2 * math.pi * freq * 3 * t)
        out.append(0.5 * envelope * value)
    return out


def main() -> None:
    samples: list[float] = []
    gap_samples = [0.0] * int(SAMPLE_RATE * GAP)
    for i, freq in enumerate(NOTES_HZ):
        samples.extend(note_samples(freq))
        if i < len(NOTES_HZ) - 1:
            samples.extend(gap_samples)

    path = "app/assets/sounds/chime.wav"
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        wav_file.writeframes(frames)
    print(f"Wrote {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


if __name__ == "__main__":
    main()
