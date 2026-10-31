"""A song (or a chord part on one instrument) to its real progression,
plus suggestions for its melody.

full mix:   separate stems -> beats on the mix -> BTC chord probabilities
            -> bass notes from the bass stem -> beat-synchronous decode
            -> melody from the vocal stem -> harmoniser alternatives
polyphonic: the same without separation; the melody is the top line.

Long work, so it runs as a background job (see jobs.py) and reports its
stage as it goes. Clips are capped at SONG_LIMIT seconds.
"""

import tempfile
from collections.abc import Callable
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf

from app.harmoniser import reasons, scoring
from app.harmoniser.vocab import Key, chord_in_key
from app.melody import extract_melody
from app.onset import music_start_samples, trim_notes
from app.pipeline import suggest
from app.songs import btc, decode, drums, models, roles
from app.timing import BeatGrid

SONG_LIMIT = 90.0
_RATE = 44100
STEM_RATE = 22050  # stems are saved at this rate: Basic Pitch's own, and small to stream
STEMS = ("vocals", "bass", "other", "drums")

Transcribe = Callable[[str], list[dict]]
Progress = Callable[[str, float], None]


def grid_from_beats(beats: np.ndarray, downbeats: np.ndarray) -> BeatGrid:
    """A constant-tempo grid fitted to detected beats: tempo from the median
    beat gap, beat 1 at the first downbeat, meter from beats per bar.
    (Songs drift a little; for a clip of a minute or so this is close.)"""
    gaps = np.diff(beats)
    beat = float(np.median(gaps)) if len(gaps) else 0.5
    meter = 4
    if len(downbeats) > 1:
        per_bar = [((beats >= a) & (beats < b)).sum() for a, b in zip(downbeats, downbeats[1:])]
        meter = int(np.clip(round(float(np.median(per_bar))), 2, 7))
    first = float(downbeats[0]) if len(downbeats) else float(beats[0]) if len(beats) else 0.0
    return BeatGrid(bpm=60.0 / beat, downbeat=first, meter=meter, guessed=False)


def bass_per_beat(bass_notes: list[dict], beats: np.ndarray, end: float) -> list[int | None]:
    """The bass pitch class sounding longest in each beat, or None."""
    bounds = list(beats) + [end]
    out: list[int | None] = []
    for a, b in zip(bounds, bounds[1:]):
        best, best_len = None, 0.0
        for n in bass_notes:
            overlap = min(n["end_time"], b) - max(n["start_time"], a)
            if overlap > best_len:
                best, best_len = n["midi_pitch"] % 12, overlap
        out.append(best if best_len > 0.05 else None)
    return out


def key_dict(key: Key, confidence: float = 0.8) -> dict:
    tonic = key.name_of(key.tonic)
    return {"tonic": tonic, "mode": key.mode, "name": f"{tonic} {key.mode}", "confidence": confidence}


def describe_recognised(segs: list[dict], melody: list[dict], grid: BeatGrid, key: Key) -> dict:
    """The song's own progression, shaped like the harmoniser's so the app
    shows it the same way: an "Original" card with a reason per chord and
    how sure the recognition was."""
    slots = scoring.span_slots(melody, grid, [(s["start"], s["end"]) for s in segs])
    chords = [chord_in_key(s["state"][0], s["state"][1], key) for s in segs]
    out = []
    for i, (seg, chord, slot) in enumerate(zip(segs, chords, slots)):
        prev = chords[i - 1] if i else None
        fit = scoring.melody_fit(chord, slot)
        why = reasons.chord_reasons(chord, slot, prev, key, 0.0, voice="the") if melody else []
        sure = seg["confidence"]
        heard = "Clearly heard in the recording." if sure >= 0.6 else (
            "Probably this; the recording is a little ambiguous here." if sure >= 0.35
            else "A best guess: the harmony is unclear here."
        )
        out.append(
            {
                "bar": max(0, grid.bar_index(seg["start"] + 1e-3)),
                "start_time": round(seg["start"], 3),
                "end_time": round(seg["end"], 3),
                "symbol": chord.symbol(key),
                "root": chord.root_name(key),
                "quality": chord.quality,
                "pitch_classes": sorted(chord.pcs, key=lambda pc: (pc - chord.root) % 12),
                "roman": chord.roman,
                "function": chord.function,
                "kind": chord.kind,
                "fit": reasons.fit_label(chord, slot, fit) if melody else "fits",
                "confidence": round(sure, 3),
                "reasons": [heard] + why,
            }
        )
    sure_overall = float(np.mean([s["confidence"] for s in segs])) if segs else 0.0
    return {
        "kind": "original",
        "source": "recognised",
        "character": "what the recording plays" + ("" if sure_overall >= 0.5 else ", partly guessed"),
        "score": 0.0,
        "chords": out,
    }


def _write(path: Path, audio: np.ndarray, rate: int) -> str:
    sf.write(str(path), audio, rate)
    return str(path)


def analyze_song(
    audio_path: str,
    transcribe: Transcribe,
    route: str,
    progress: Progress = lambda stage, fraction: None,
    use_llm: bool = True,
    work_dir: Path | None = None,
    notes: list[dict] | None = None,
    start: float | None = None,
    alternatives: bool = True,
) -> dict:
    """`notes` (Basic Pitch on the whole file) and `start` (where the music
    begins) can be passed in when the caller already has them, so the mix
    isn't transcribed or measured twice."""
    y, _ = librosa.load(audio_path, sr=_RATE, mono=False, duration=SONG_LIMIT)
    stereo = np.stack([y, y]) if y.ndim == 1 else y[:2]
    mono = stereo.mean(axis=0)
    end = len(mono) / _RATE
    if start is None:
        start = music_start_samples(mono, _RATE)
    work = work_dir or Path(tempfile.mkdtemp(prefix="song_"))
    work.mkdir(parents=True, exist_ok=True)

    stem_files: dict[str, str] = {}
    if route == "full_mix":
        progress("Separating the instruments", 0.05)
        stems = models.separate(stereo, _RATE)
        # Saved mono at 22.05 kHz: what Basic Pitch reads, and what the app
        # streams when you solo a part.
        for name in STEMS:
            audio = librosa.resample(stems[name], orig_sr=_RATE, target_sr=STEM_RATE)
            stem_files[name] = _write(work / f"{name}.wav", audio, STEM_RATE)
    else:
        stems = {}

    progress("Finding the beat", 0.45)
    beat_times, downbeat_times = models.beats(mono, _RATE)
    if len(beat_times) < 4:
        raise ValueError("Couldn't find a steady beat in this recording.")

    progress("Hearing the chords", 0.6)
    probs = models.chord_probabilities(librosa.resample(mono, orig_sr=_RATE, target_sr=btc.SAMPLE_RATE))
    emissions = decode.beat_emissions(probs, btc.FRAME_SECONDS, beat_times, end)
    key = decode.estimate_key(emissions)
    flags = [bool(np.any(np.abs(downbeat_times - b) < 0.07)) for b in beat_times]

    progress("Following the bass", 0.7)
    bass_notes = transcribe(stem_files["bass"]) if "bass" in stem_files else []
    bass_pcs = bass_per_beat(bass_notes, beat_times, end) if bass_notes else None
    path, confidence = decode.decode(emissions, flags, key, bass_pcs)
    segs = decode.segments(path, confidence, beat_times, end)

    progress("Finding the melody", 0.8)
    if "vocals" in stem_files:
        all_notes: list[dict] = []
        melody_notes = trim_notes(transcribe(stem_files["vocals"]), start)
    else:
        # Lead-in ghosts are trimmed once here, for the melody and the
        # harmony part alike.
        all_notes = trim_notes(notes if notes is not None else transcribe(audio_path), start)
        melody_notes = all_notes
    melody = extract_melody(melody_notes)

    progress("Hearing what each instrument plays", 0.86)
    downbeats = [float(d) for d in downbeat_times]
    parts = [_part("melody", "Melody", "vocals" if stem_files else None, melody, roles.melody_role(melody, segs))]
    if "bass" in stem_files:
        parts.append(_part("bass", "Bass", "bass", bass_notes, roles.bass_role(bass_notes, segs, downbeats)))
    harmony_notes = transcribe(stem_files["other"]) if "other" in stem_files else all_notes
    parts.append(_part("harmony", "Harmony", "other" if stem_files else None, harmony_notes, roles.harmony_role(harmony_notes)))
    grid = grid_from_beats(beat_times, downbeat_times)
    if "drums" in stem_files:
        role, hits = drums.analyse(stems["drums"], mono, _RATE, beat_times, downbeat_times, grid.meter)
        parts.append(_part("drums", "Drums", "drums", hits, role))

    progress("Suggesting alternatives", 0.92)
    key_info = key_dict(key)
    original = describe_recognised(segs, melody, grid, key)
    # Skippable for a full mix's quick first answer: its background job
    # re-harmonises from the separated vocal melody anyway.
    suggested = suggest(melody, grid, key=key_info, use_llm=use_llm) if melody and alternatives else {
        "progressions": [], "insight": None, "grid": grid.to_dict(0, end)
    }
    return {
        "route": route,
        "route_note": None,
        "notes": melody_notes,
        "melody": melody,
        "grid": grid.to_dict(min(0.0, grid.downbeat), end),
        "key": key_info,
        "progressions": [original] + suggested["progressions"],
        "insight": _song_insight(segs, key),
        "duration": end,
        "music_start": start,
        "clipped": end >= SONG_LIMIT - 0.5,
        "parts": parts,
        "stems": sorted(stem_files),
    }


def _part(part_id: str, name: str, stem: str | None, notes: list[dict], role: dict) -> dict:
    return {
        "id": part_id,
        "name": name,
        "stem": stem,
        "notes": notes,
        "role": role["summary"],
        "detail": role.get("detail"),
    }





def _song_insight(segs: list[dict], key: Key) -> str | None:
    if not segs:
        return None
    symbols = []
    for s in segs:
        c = chord_in_key(s["state"][0], s["state"][1], key)
        if not symbols or symbols[-1] != c.roman:
            symbols.append(c.roman)
    # The most repeated four-chord loop, if the song has one.
    loops: dict[tuple, int] = {}
    for i in range(len(symbols) - 3):
        loop = tuple(symbols[i : i + 4])
        loops[loop] = loops.get(loop, 0) + 1
    if loops:
        loop, count = max(loops.items(), key=lambda kv: kv[1])
        if count >= 2:
            return f"In {key.name_of(key.tonic)} {key.mode}, it keeps cycling {' – '.join(loop)}."
    return f"In {key.name_of(key.tonic)} {key.mode}, built mostly on {', '.join(dict.fromkeys(symbols[:4]))}."
