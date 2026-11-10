"""Where the music in a recording actually starts.

People press record, then take a breath, settle the phone or count
themselves in. Basic Pitch hears that lead-in as notes: mains hum and
rumble come out as confident-looking low notes (a "G1" at 0.4 confidence
is typical), and those ghosts then become the melody's first note, which
drags the estimated beat grid and the first chord back into the silence.

This finds the first moment that is clearly louder than the recording's
own background and stays that way, ignoring everything below ~70 Hz where
hum and handling noise live. Pure numpy on a sample array so it can be
tested without files.
"""

import numpy as np

_FRAME = 1024
_HOP = 256
_HIGHPASS_HZ = 70.0
_MIN_RISE_DB = 12.0  # the music must be at least this far above the background
_SUSTAIN = 0.12  # seconds it must stay up: a click or a tap isn't music
_PREROLL = 0.06  # start a touch before the detected rise, so attacks survive
_MIN_LEAD = 0.25  # a lead-in shorter than this isn't worth trimming


def _frame_db(y: np.ndarray) -> np.ndarray:
    """RMS level (dB) of each FRAME-long window, every HOP samples. Windowed
    energy comes from one cumulative sum of squares, so it's O(N) in time
    and memory (no frames x window matrix: that was ~250 MB for 90 s at
    44.1 kHz)."""
    c = np.concatenate([[0.0], np.cumsum(y * y)])
    starts = np.arange(0, len(y) - _FRAME + 1, _HOP)
    energy = np.maximum(c[starts + _FRAME] - c[starts], 0.0) / _FRAME
    return 10 * np.log10(energy + 1e-20)


def music_start_samples(y: np.ndarray, sr: int) -> float:
    """Seconds from the start of `y` (mono float) to where the music
    begins; 0.0 when it starts straight away or never clearly rises."""
    if y.size < _FRAME * 4:
        return 0.0
    from scipy.ndimage import median_filter
    from scipy.signal import butter, sosfilt

    sos = butter(4, _HIGHPASS_HZ / (sr / 2), btype="highpass", output="sos")
    db = _frame_db(sosfilt(sos, y.astype(np.float64)))
    # The background is the quietest *stretch* (a lightly smoothed minimum),
    # not a low percentile of the whole clip: a 2 s lead-in is only 2% of a
    # 90 s song, so any percentile above that lands inside the music and
    # the lead-in is never seen.
    smooth = median_filter(db, size=max(3, int(0.2 * sr / _HOP)), mode="nearest")
    floor = float(smooth.min())
    loud = float(np.percentile(db, 95))
    if loud - floor < _MIN_RISE_DB:
        return 0.0  # no quiet lead-in to speak of (or no music at all)
    threshold = floor + max(_MIN_RISE_DB, 0.35 * (loud - floor))
    above = (db > threshold).astype(np.int32)
    need = max(1, int(round(_SUSTAIN * sr / _HOP)))
    # The first run of `need` frames all above the threshold.
    runs = np.convolve(above, np.ones(need, dtype=np.int32), mode="valid")
    hits = np.flatnonzero(runs >= need)
    if hits.size == 0:
        return 0.0
    start = hits[0] * _HOP / sr - _PREROLL
    return round(start, 3) if start >= _MIN_LEAD else 0.0


def music_start(audio_path: str, seconds: float = 90.0) -> float:
    """`music_start_samples` for an audio file (0.0 if it can't be read)."""
    import librosa

    try:
        y, sr = librosa.load(audio_path, sr=22050, mono=True, duration=seconds)
    except Exception:
        return 0.0
    return music_start_samples(y, sr)


def trim_notes(notes: list[dict], start: float) -> list[dict]:
    """Drops notes heard in the lead-in before `start`. A note that began a
    hair early (its attack straddles the detected rise) is kept."""
    if start <= 0:
        return notes
    return [n for n in notes if n["start_time"] >= start - 0.12]
