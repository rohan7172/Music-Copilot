"""Turning Basic Pitch's note list into one melody line, deciding what kind
of take it is, and finding the melody's key.

Basic Pitch reports every note it hears, including overtone ghosts and, for
a song, every instrument at once. The harmoniser needs a single tune, so
this keeps the top line ("skyline"), merges repeats and drops blips.
"""

from music21 import key as m21key
from music21 import note as m21note
from music21 import stream

from app.harmony import _describe_key, without_overtones
from app.timing import BeatGrid

_MIN_CONFIDENCE = 0.3
_MIN_NOTE = 0.08  # seconds; shorter notes are blips
_FRAGMENT = 0.24  # seconds; a same-pitch piece this short is part of its neighbour


def classify_input(notes: list[dict]) -> str:
    """'melody' for a single line, 'polyphonic' for one instrument playing
    chords, 'full_mix' for a band or a song.

    Measured as the average number of confident notes sounding at once,
    over the time anything is sounding at all.
    """
    confident = [n for n in notes if n["confidence"] >= _MIN_CONFIDENCE]
    if not confident:
        return "melody"
    edges = sorted(
        [(n["start_time"], 1) for n in confident] + [(n["end_time"], -1) for n in confident]
    )
    sounding = 0
    last_t = edges[0][0]
    busy = 0.0
    weighted = 0.0
    for t, delta in edges:
        span = t - last_t
        if sounding > 0 and span > 0:
            busy += span
            weighted += span * sounding
        sounding += delta
        last_t = t
    polyphony = weighted / busy if busy > 0 else 1.0
    if polyphony < 1.35:
        return "melody"
    if polyphony < 4.0:
        return "polyphonic"
    return "full_mix"


def extract_melody(notes: list[dict]) -> list[dict]:
    """The top line: at every moment the highest sounding note wins. A lower
    note that outlasts the tune above it carries on once the tune stops."""
    candidates = [n for n in without_overtones(notes) if n["confidence"] >= _MIN_CONFIDENCE]
    if not candidates:
        return []
    times = sorted({t for n in candidates for t in (n["start_time"], n["end_time"])})
    segments: list[dict] = []
    for a, b in zip(times, times[1:]):
        sounding = [
            n
            for n in candidates
            if n["start_time"] <= a + 1e-9 and n["end_time"] >= b - 1e-9
        ]
        if not sounding:
            continue
        top = max(sounding, key=lambda n: (n["midi_pitch"], n["confidence"]))
        if segments and segments[-1]["_source"] is top and abs(segments[-1]["end_time"] - a) < 1e-9:
            segments[-1]["end_time"] = b
        else:
            segments.append({**top, "start_time": a, "end_time": b, "_source": top})

    merged: list[dict] = []
    for seg in segments:
        n = {k: v for k, v in seg.items() if k != "_source"}
        if n["end_time"] - n["start_time"] < _MIN_NOTE:
            continue
        # Basic Pitch reports a re-sung repeated note as a new event starting
        # right where the last one ended, so abutting isn't enough to merge:
        # only a short fragment (a split-up note) joins its neighbour.
        if (
            merged
            and merged[-1]["midi_pitch"] == n["midi_pitch"]
            and n["start_time"] - merged[-1]["end_time"] <= 0.05
            and min(
                n["end_time"] - n["start_time"],
                merged[-1]["end_time"] - merged[-1]["start_time"],
            )
            < _FRAGMENT
        ):
            merged[-1]["end_time"] = n["end_time"]
            merged[-1]["confidence"] = max(merged[-1]["confidence"], n["confidence"])
            continue
        merged.append(n)
    return merged


def detect_melody_key(melody: list[dict], grid: BeatGrid | None = None) -> dict | None:
    """Krumhansl-Schmuckler key of the melody, each note weighted by how
    long it lasts and how strong a beat it starts on, plus the runner-up."""
    if not melody:
        return None
    s = stream.Stream()
    for n in melody:
        length = max(n["end_time"] - n["start_time"], 0.05)
        strength = grid.strength(n["start_time"]) if grid else 0.6
        s.insert(
            n["start_time"],
            m21note.Note(midi=n["midi_pitch"], quarterLength=length * (0.4 + strength)),
        )
    found: m21key.Key = s.analyze("krumhansl")
    described = _describe_key(found)
    alternates = getattr(found, "alternateInterpretations", None) or []
    if alternates:
        runner = _describe_key(alternates[0])
        described["runner_up"] = {k: runner[k] for k in ("tonic", "mode", "name", "confidence")}
    return described
