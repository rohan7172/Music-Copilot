"""Recognising what the drums play: whether there are any, which kit piece
each hit is, and the groove they make.

Works on the separated drum stem, always measured against the full mix:
Demucs's drum stem for a drumless song is quiet leakage, and a detector
scaled to the stem's own level (as the first version was) turns that
leakage into hundreds of "hits".

1. presence: is the stem audible at all, and do its hits behave like a
   drummer's (on the beat grid, across the song) rather than leakage?
2. detect_hits: band-split the stem (kick low, snare mid, hi-hat high) and
   find sharp rises in each band that are loud relative to the mix; merge
   bands that fire together into one stroke and name its pieces.
3. groove: where each piece lands in the bar, from the real beat list.

Pure numpy/scipy on sample arrays, so it's tested on synthesised drums.
"""

from collections import Counter

import numpy as np

_SR = 22050
_HOP = 256  # ~11.6 ms frames
_WINDOW = 2.0  # seconds per presence window

# Loudness alone can't tell real drums from leakage: it depends on the
# mix's balance (a drumless song's leakage measured ~17 dB under the mix,
# a real rock beat under a loud vocal ~15 dB under). So the level gate only
# asks "audible at all?", and the deciding test is structure: real drums
# hit on the beat grid, bar after bar; leakage doesn't.
_PRESENT_DB = -26.0
_MIN_PRESENT_SHARE = 0.2  # of the clip, audible at all
_MIN_ALIGNED = 0.8  # share of hits within 50 ms of an eighth-note position
_MIN_BAR_COVERAGE = 0.3  # share of bars with hits (drums may sit out a verse)

_RISE_DB = 9.0  # a hit is a sudden jump of at least this much in its band
_RISE_FRAMES = 4  # ...compared with the quietest of the previous ~45 ms
_MIN_GAP = 0.06  # seconds between hits in one band
_GROUP = 0.035  # band hits this close together are one stroke

# How far under the mix's level each band's peak may sit and still count.
_BAND_GAP_DB = {"kick": 24.0, "snare": 24.0, "hat": 32.0}

# General MIDI drum-map notes, so hits travel as ordinary notes.
PIECE_NOTE = {"kick": 36, "snare": 38, "hat": 42}
PIECE_NAME = {"kick": "Kick", "snare": "Snare", "hat": "Hi-hat"}


def _resample(y: np.ndarray, sr: int) -> np.ndarray:
    if sr == _SR:
        return y.astype(np.float64)
    import librosa

    return librosa.resample(y.astype(np.float64), orig_sr=sr, target_sr=_SR)


def _frame_db(y: np.ndarray, frame: int = 512) -> np.ndarray:
    """RMS level (dB) per hop, from a cumulative sum of squares (O(N))."""
    padded = np.concatenate([np.zeros(frame // 2), y, np.zeros(frame // 2)])
    c = np.concatenate([[0.0], np.cumsum(padded * padded)])
    starts = np.arange(0, len(y), _HOP)
    energy = np.maximum(c[starts + frame] - c[starts], 0.0) / frame
    return 10 * np.log10(energy + 1e-12)


def _bands(y: np.ndarray) -> dict[str, np.ndarray]:
    from scipy.signal import butter, sosfilt

    nyq = _SR / 2
    return {
        "kick": sosfilt(butter(4, 120 / nyq, btype="low", output="sos"), y),
        "snare": sosfilt(butter(4, [180 / nyq, 2500 / nyq], btype="band", output="sos"), y),
        "hat": sosfilt(butter(4, 6000 / nyq, btype="high", output="sos"), y),
    }


def presence(drums: np.ndarray, mix: np.ndarray, sr: int) -> tuple[float, list[tuple[float, float]]]:
    """(share of the clip with real drums, the spans where they play)."""
    d = _resample(drums, sr)
    m = _resample(mix, sr)
    n = int(_WINDOW * _SR)
    spans, present, counted = [], 0, 0
    for i in range(0, min(len(d), len(m)) - n // 2, n):
        dd = d[i : i + n]
        mm = m[i : i + n]
        mix_db = 10 * np.log10(np.mean(mm * mm) + 1e-12)
        if mix_db < -60:
            continue  # silence: says nothing either way
        counted += 1
        if 10 * np.log10(np.mean(dd * dd) + 1e-12) - mix_db >= _PRESENT_DB:
            present += 1
            spans.append((i / _SR, (i + len(dd)) / _SR))
    share = present / counted if counted else 0.0
    merged: list[tuple[float, float]] = []
    for a, b in spans:
        if merged and a - merged[-1][1] < 1e-6:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return share, merged


def _band_hits(level: np.ndarray, mix_level: np.ndarray, gap_db: float) -> list[tuple[int, float]]:
    """(frame, strength in dB relative to the mix) for each hit in a band."""
    hits: list[tuple[int, float]] = []
    min_gap = int(_MIN_GAP * _SR / _HOP)
    for t in range(_RISE_FRAMES, len(level) - 2):
        peak = level[t]
        if peak < level[t - 1] or peak < level[t + 1] or peak < level[t + 2]:
            continue
        rise = peak - level[t - _RISE_FRAMES : t].min()
        relative = peak - mix_level[t]
        if rise < _RISE_DB or relative < -gap_db:
            continue
        if hits and t - hits[-1][0] < min_gap:
            if relative > hits[-1][1]:
                hits[-1] = (t, relative)
            continue
        hits.append((t, relative))
    return hits


def detect_hits(drums: np.ndarray, mix: np.ndarray, sr: int, spans: list[tuple[float, float]] | None = None) -> list[dict]:
    """Drum strokes as [{time, pieces, strength}], pieces a subset of
    {"kick", "snare", "hat"}. Only hits inside `spans` (where drums are
    present) are kept, when given."""
    d = _resample(drums, sr)
    m = _resample(mix, sr)
    mix_level = _frame_db(m)
    levels = {name: _frame_db(band) for name, band in _bands(d).items()}
    events = []
    for name, level in levels.items():
        n = min(len(level), len(mix_level))
        for frame, strength in _band_hits(level[:n], mix_level[:n], _BAND_GAP_DB[name]):
            events.append((frame * _HOP / _SR, name, strength, frame))
    events.sort()

    strokes: list[dict] = []
    group: list[tuple] = []

    def flush():
        if not group:
            return
        by_piece = {name: (strength, frame) for _, name, strength, frame in group}
        pieces = set()
        if "kick" in by_piece:
            # A snare's body (~200 Hz) leaks into the kick band; it's only a
            # kick if the low band is about as loud as the mid band.
            frame = by_piece["kick"][1]
            if levels["kick"][frame] >= levels["snare"][frame] - 3:
                pieces.add("kick")
        if "snare" in by_piece:
            # A kick's attack click leaks into the snare band; it's only a
            # snare if the mid band is about as strong as the low one.
            kick = by_piece.get("kick")
            if kick is None or by_piece["snare"][0] >= kick[0] - 6:
                pieces.add("snare")
        if "hat" in by_piece:
            # A snare's rattle reaches the hi-hat band too: a hat on the
            # same stroke must stand clearly above the snare band.
            frame = by_piece["hat"][1]
            if "snare" not in pieces or levels["hat"][frame] >= levels["snare"][frame] + 4:
                pieces.add("hat")
        if pieces:
            strokes.append(
                {
                    "time": round(group[0][0], 3),
                    "pieces": sorted(pieces),
                    "strength": round(max(by_piece[p][0] for p in pieces), 2),
                }
            )
        group.clear()

    for event in events:
        if group and event[0] - group[0][0] > _GROUP:
            flush()
        group.append(event)
    flush()

    if spans is not None:
        strokes = [s for s in strokes if any(a <= s["time"] < b for a, b in spans)]
    return strokes


def bar_position(t: float, beats: np.ndarray, downbeats: np.ndarray) -> tuple[int, float] | None:
    """(beats since the bar's downbeat, fraction of the way to the next
    beat) for time t, from the actual beat list: no drift from assuming a
    constant tempo."""
    i = int(np.searchsorted(beats, t + 0.04)) - 1
    if i < 0 or i + 1 >= len(beats):
        return None
    d = downbeats[downbeats <= beats[i] + 0.04]
    if not len(d):
        return None
    index_in_bar = int(np.sum((beats >= d[-1] - 0.04) & (beats < beats[i] - 0.04)))
    frac = (t - beats[i]) / (beats[i + 1] - beats[i])
    return index_in_bar, float(np.clip(frac, -0.5, 1.0))


def groove(strokes: list[dict], beats, downbeats, meter: int) -> dict:
    """Where each piece regularly lands, in eighth-note steps from beat 1
    (0 = beat 1, 1 = the "and" of 1, ...), plus hits per bar."""
    beats = np.asarray(beats, dtype=float)
    downbeats = np.asarray(downbeats, dtype=float)
    steps = 2 * meter
    counts: dict[str, Counter] = {p: Counter() for p in PIECE_NOTE}
    bars_seen: set[int] = set()
    for s in strokes:
        pos = bar_position(s["time"], beats, downbeats)
        if pos is None:
            continue
        index, frac = pos
        step = int(round((index + frac) * 2)) % steps
        bars_seen.add(int(np.sum(downbeats <= s["time"] + 0.04)))
        for p in s["pieces"]:
            counts[p][step] += 1
    bars = max(len(bars_seen), 1)
    regular = {p: sorted(k for k, v in c.items() if v / bars >= 0.45) for p, c in counts.items()}
    per_bar = {p: sum(c.values()) / bars for p, c in counts.items()}
    return {"regular": regular, "per_bar": per_bar, "bars": len(bars_seen), "meter": meter}


def _step_name(step: int) -> str:
    beat = step // 2 + 1
    return str(beat) if step % 2 == 0 else f"the & of {beat}"


def _list(steps: list[int]) -> str:
    names = [_step_name(s) for s in steps]
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def describe(g: dict) -> dict:
    """The Drums part's role sentence, from the groove facts."""
    meter, reg, per_bar = g["meter"], g["regular"], g["per_bar"]
    steps = 2 * meter
    total = sum(per_bar.values())
    beats_all = list(range(0, steps, 2))
    phrases = []
    if reg["kick"]:
        phrases.append("kick on every beat (four on the floor)" if reg["kick"] == beats_all and meter == 4 else f"kick on {_list(reg['kick'])}")
    if reg["snare"]:
        backbeat = meter == 4 and set(reg["snare"]) >= {2, 6} and not set(reg["snare"]) & {0, 4}
        phrases.append(f"snare on {_list(reg['snare'])}" + (" (a backbeat)" if backbeat else ""))
    if reg["hat"]:
        # A snare struck with the hat masks it (to the ear as to the
        # detector), so a hat whose only gaps are the snare's hits is steady.
        hat_or_masked = set(reg["hat"]) | set(reg["snare"])
        if per_bar["hat"] >= 1.6 * steps:
            phrases.append("hi-hat in sixteenths")
        elif hat_or_masked >= set(range(steps)) and len(reg["hat"]) >= steps // 2:
            phrases.append("hi-hat on every eighth note")
        elif hat_or_masked >= set(beats_all) and set(reg["hat"]) <= set(beats_all):
            phrases.append("hi-hat on every beat")
        elif reg["hat"] == list(range(1, steps, 2)):
            phrases.append("hi-hat on the off-beats (the &s)")
        else:
            phrases.append(f"hi-hat on {_list(reg['hat'])}")
    if not phrases:
        return {
            "summary": "Drums are there, but loose: no steady pattern repeats bar to bar.",
            "detail": f"About {total:.0f} hits a bar.",
        }
    feel = ""
    if meter == 4 and reg["kick"] == beats_all and set(reg["snare"]) >= {2, 6}:
        feel = ": a dance groove"
    elif meter == 4 and set(reg["kick"]) & {0} and set(reg["snare"]) >= {2, 6}:
        feel = ": a straight rock and pop groove"
    elif meter == 3 and 0 in reg["kick"]:
        feel = ": a waltz feel, one strong beat in three"
    sentence = ", ".join(phrases)
    detail = (
        f"About {total:.0f} hits a bar: {per_bar['kick']:.0f} kick, {per_bar['snare']:.0f} snare, "
        f"{per_bar['hat']:.0f} hi-hat."
    )
    return {"summary": sentence[0].upper() + sentence[1:] + feel + ".", "detail": detail}


NO_DRUMS = {
    "summary": "No drums to speak of: the rhythm comes from the other instruments.",
    "detail": None,
}


def is_drumming(strokes: list[dict], beats, downbeats) -> bool:
    """Whether detected strokes behave like a drummer: on the beat grid
    (within 50 ms of an eighth-note position, from the real beats) and
    spread across the song, not a few scattered bursts of leakage."""
    beats = np.asarray(beats, dtype=float)
    downbeats = np.asarray(downbeats, dtype=float)
    if len(strokes) < 4 or len(beats) < 4 or len(downbeats) < 2:
        return False
    eighths = np.sort(np.concatenate([beats, (beats[:-1] + beats[1:]) / 2]))
    times = np.array([s["time"] for s in strokes])
    aligned = float(np.mean(np.min(np.abs(eighths[None, :] - times[:, None]), axis=1) < 0.05))
    bars = np.searchsorted(downbeats, times, side="right")
    coverage = len(set(bars.tolist()) - {0}) / max(len(downbeats) - 1, 1)
    return aligned >= _MIN_ALIGNED and coverage >= _MIN_BAR_COVERAGE


def analyse(drums: np.ndarray, mix: np.ndarray, sr: int, beats, downbeats, meter: int) -> tuple[dict, list[dict]]:
    """(role {summary, detail}, hits as notes for the Drums lens)."""
    share, spans = presence(drums, mix, sr)
    if share < _MIN_PRESENT_SHARE:
        return NO_DRUMS, []
    strokes = detect_hits(drums, mix, sr, spans)
    if not is_drumming(strokes, beats, downbeats):
        return NO_DRUMS, []
    role = describe(groove(strokes, beats, downbeats, meter))
    notes = [
        {
            "pitch": PIECE_NAME[p],
            "midi_pitch": PIECE_NOTE[p],
            "start_time": s["time"],
            "end_time": round(s["time"] + 0.09, 3),
            "confidence": 0.9,
        }
        for s in strokes
        for p in s["pieces"]
    ]
    return role, notes
