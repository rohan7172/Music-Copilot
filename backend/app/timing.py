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


def estimate_grid(melody: list[dict], meter: int | None = None) -> BeatGrid:
    """Tempo, beat phase, meter (3 or 4, unless given) and downbeat
    estimated from the melody's onsets."""
    if len(melody) < 2:
        start = melody[0]["start_time"] if melody else 0.0
        return BeatGrid(bpm=90.0, downbeat=start, meter=meter or 4)

    bpm = _estimate_tempo(melody)
    beat, phase = _refine_beat(melody, 60.0 / bpm)
    meter = meter or _detect_meter(melody, beat, phase)
    downbeat = _best_downbeat(melody, beat, phase, meter)
    return BeatGrid(bpm=60.0 / beat, downbeat=downbeat, meter=meter)


def _alignment(melody: list[dict], periods: np.ndarray, phases_frac: np.ndarray) -> np.ndarray:
    """How well onsets sit on beats for every (period, phase) pair:
    (len(periods), len(phases_frac)), phase given as a fraction of a beat."""
    t = np.array([n["start_time"] for n in melody])
    w = np.array([0.3 + _weight(n) for n in melody])
    pos = (t[None, None, :] / periods[:, None, None]) - phases_frac[None, :, None]
    off = pos - np.round(pos)
    return (w * np.exp(-((off / 0.08) ** 2))).sum(axis=2)


def _refine_beat(melody: list[dict], beat: float) -> tuple[float, float]:
    """The tempogram's tempo is close but rarely exact, and over a
    20-second take a 2% error slides the grid a whole beat off the tune by
    the end. Searches tempo within ±5% and phase together for the pair that
    puts the most note weight on beats. Returns (beat length, phase)."""
    periods = beat * np.linspace(0.95, 1.05, 101)
    fracs = np.arange(64) / 64
    score = _alignment(melody, periods, fracs)
    # Prefer staying near the tempogram's answer when scores tie.
    score *= 1 - 0.03 * np.linspace(-1, 1, len(periods))[:, None] ** 2
    i, j = np.unravel_index(int(score.argmax()), score.shape)
    best = float(periods[i])
    return best, float(fracs[j] * best)


def _detect_meter(melody: list[dict], beat: float, phase: float) -> int:
    """3 or 4 beats to the bar, from how the melody's accents repeat: long
    notes and phrase starts recur every bar, so the per-beat accent pattern
    correlates with itself at a lag of one bar. A waltz repeats every 3
    beats, almost everything else every 4 (or 2, which 4 covers)."""
    first = melody[0]["start_time"]
    count = int((melody[-1]["end_time"] - first) / beat) + 2
    if count < 12:
        return 4  # too short to tell; 4/4 is the safe bet
    accent = np.zeros(count)
    for n in melody:
        k = int(round((n["start_time"] - phase) / beat - math.floor((first - phase) / beat)))
        if 0 <= k < count:
            accent[k] += _weight(n) + 0.1
    a = accent - accent.mean()

    def corr(lag: int) -> float:
        x, y = a[:-lag], a[lag:]
        d = math.sqrt(float((x * x).sum() * (y * y).sum())) or 1.0
        return float((x * y).sum()) / d

    three = (corr(3) + corr(6)) / 2
    four = (corr(4) + corr(8)) / 2
    return 3 if three > four + 0.08 else 4


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
