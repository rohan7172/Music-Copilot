#!/usr/bin/env python3
"""Synthesizes the recording click: a short, mostly unpitched tick.

Kept under 30 ms and built mostly from filtered noise, so if it leaks
from the speaker into the microphone, Basic Pitch hears it as a blip it
drops (notes under 80 ms are discarded) rather than as a melody note.
Run with `python3 scripts/generate_click.py` to regenerate
`app/assets/sounds/click.wav`.
"""

import math
import random
import struct
import wave

SAMPLE_RATE = 44100
LENGTH = 0.028

random.seed(7)
n = int(SAMPLE_RATE * LENGTH)
samples = []
low = 0.0
for i in range(n):
    t = i / SAMPLE_RATE
    envelope = math.exp(-t * 180)
    noise = random.uniform(-1, 1)
    low += 0.35 * (noise - low)  # soften the noise's top end
    body = 0.35 * math.sin(2 * math.pi * 1900 * t)
    samples.append(0.7 * envelope * (0.75 * low + body))

with wave.open("app/assets/sounds/click.wav", "wb") as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(SAMPLE_RATE)
    out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
