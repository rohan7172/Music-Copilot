"""The beat grid a melody is harmonised against.

A hummed tune has no drums, so the bars and beats are either given (the app
played a click while recording) or estimated from the melody's own note
onsets: tempo from an onset tempogram, beat phase from where onsets land,
and the downbeat from where the long notes fall. An estimated grid is
marked `guessed` so the app can offer to nudge it.
"""

import math
from dataclasses import dataclass

import librosa
import numpy as np

_ENVELOPE_RATE = 100  # onset-envelope frames per second
_MIN_BPM = 60.0
_MAX_BPM = 160.0


@dataclass(frozen=True)
class BeatGrid:
    bpm: float
    # Time (seconds) of a bar's first beat; bars run from here in both
    # directions, so pickup notes before it still land in a bar.
    downbeat: float
    meter: int = 4
    guessed: bool = True

    @property
    def beat_length(self) -> float:
        return 60.0 / self.bpm

    @property
    def bar_length(self) -> float:
        return self.beat_length * self.meter

    def beat_position(self, t: float) -> float:
        """Beats since the downbeat (may be negative or fractional)."""
        return (t - self.downbeat) / self.beat_length

    def bar_index(self, t: float) -> int:
        return math.floor((t - self.downbeat) / self.bar_length + 1e-9)

    def bar_start(self, index: int) -> float:
        return self.downbeat + index * self.bar_length

    def strength(self, t: float) -> float:
        """How metrically strong time t is: beat 1 > the bar's middle beat >
        other beats > off-beat eighths > anything else."""
        pos = self.beat_position(t) % self.meter
        nearest = round(pos)
        if abs(pos - nearest) <= 0.12:
            beat = nearest % self.meter
            if beat == 0:
                return 1.0
            if self.meter == 4 and beat == 2:
                return 0.75
            return 0.5
        if abs(pos - (math.floor(pos) + 0.5)) <= 0.12:
            return 0.3
        return 0.2

    def beats(self, start: float, end: float) -> list[dict]:
        """Every beat between start and end, with its strength."""
        first = math.ceil((start - self.downbeat) / self.beat_length - 1e-9)
        out = []
        i = first
        while (t := self.downbeat + i * self.beat_length) <= end + 1e-9:
            out.append({"time": round(t, 3), "downbeat": i % self.meter == 0})
            i += 1
        return out

    def to_dict(self, start: float, end: float) -> dict:
        return {
            "bpm": round(self.bpm, 2),
            "downbeat": round(self.downbeat, 3),
            "meter": self.meter,
            "guessed": self.guessed,
            "beats": self.beats(start, end),
        }

    @staticmethod
    def from_dict(d: dict) -> "BeatGrid":
        return BeatGrid(
            bpm=float(d["bpm"]),
            downbeat=float(d["downbeat"]),
            meter=int(d.get("meter", 4)),
            guessed=bool(d.get("guessed", True)),
        )


def grid_from_click(bpm: float, first_beat: float, meter: int = 4) -> BeatGrid:
    """The grid when the app played a click: exact, not guessed."""
    return BeatGrid(bpm=bpm, downbeat=first_beat, meter=meter, guessed=False)


def estimate_grid(melody: list[dict], meter: int = 4) -> BeatGrid:
    """Tempo, beat phase and downbeat estimated from the melody's onsets."""
    if len(melody) < 2:
        start = melody[0]["start_time"] if melody else 0.0
        return BeatGrid(bpm=90.0, downbeat=start, meter=meter)

    bpm = _estimate_tempo(melody)
    beat = 60.0 / bpm
    phase = _best_phase(melody, beat)
    downbeat = _best_downbeat(melody, beat, phase, meter)
    return BeatGrid(bpm=bpm, downbeat=downbeat, meter=meter)


def _weight(note: dict) -> float:
    """Longer, more confident notes say more about where the beat is."""
    length = note["end_time"] - note["start_time"]
    return min(length, 1.5) * max(note.get("confidence", 0.6), 0.3)


def _estimate_tempo(melody: list[dict]) -> float:
    end = max(n["end_time"] for n in melody) + 1.0
    envelope = np.zeros(int(end * _ENVELOPE_RATE) + 1)
    for n in melody:
        envelope[int(n["start_time"] * _ENVELOPE_RATE)] += 0.4 + _weight(n)
    # A little smoothing so near-simultaneous onsets reinforce each other.
    envelope = np.convolve(envelope, np.hanning(5), mode="same")
    tempo = float(
        librosa.feature.tempo(
            onset_envelope=envelope,
            sr=_ENVELOPE_RATE,
            hop_length=1,
            start_bpm=100,
            max_tempo=_MAX_BPM * 1.5,
        )[0]
    )
    if not np.isfinite(tempo) or tempo <= 0:
        return 90.0
    while tempo > _MAX_BPM:
        tempo /= 2
    while tempo < _MIN_BPM:
        tempo *= 2
    return tempo


def _best_phase(melody: list[dict], beat: float) -> float:
    """The beat offset (0..beat) that puts the most note weight on beats."""
    best, best_score = 0.0, -math.inf
    for k in range(48):
        phase = beat * k / 48
        score = 0.0
        for n in melody:
            off = ((n["start_time"] - phase) / beat) % 1
            distance = min(off, 1 - off)
            score += (0.3 + _weight(n)) * math.exp(-((distance / 0.08) ** 2))
        if score > best_score:
            best, best_score = phase, score
    return best


def _best_downbeat(melody: list[dict], beat: float, phase: float, meter: int) -> float:
    """Which beat is beat 1. Long notes land on strong beats, but in 4/4
    beat 3 is strong too, so that alone is ambiguous by half a bar. The
    deciding cue is phrasing: a note right after a long note or a rest
    starts a new phrase, and phrases usually start on beat 1 (as does the
    whole tune, unless it has a pickup). Returns the downbeat at or just
    before the first note."""
    first = melody[0]["start_time"]
    phrase_starts = [melody[0]] + [
        n
        for prev, n in zip(melody, melody[1:])
        if prev["end_time"] - prev["start_time"] >= 1.4 * beat
        or n["start_time"] - prev["end_time"] >= 0.75 * beat
    ]
    best, best_score = phase, -math.inf
    for shift in range(meter):
        downbeat = phase + shift * beat
        grid = BeatGrid(bpm=60.0 / beat, downbeat=downbeat, meter=meter)
        score = 0.0
        for n in melody:
            strength = grid.strength(n["start_time"])
            if strength >= 0.75:
                score += strength * (_weight(n) + 0.2)
        for n in phrase_starts:
            if grid.strength(n["start_time"]) == 1.0:
                score += 1.2
        if score > best_score:
            best, best_score = downbeat, score
    bar = beat * meter
    return best - math.ceil((best - first) / bar - 1e-9) * bar
