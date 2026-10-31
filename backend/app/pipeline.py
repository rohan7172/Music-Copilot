"""From Basic Pitch's notes to suggested progressions.

notes -> route (melody / polyphonic / full mix) -> one melody line ->
beat grid (from the click, or estimated) -> key -> harmoniser (Safe,
Colourful, Surprising) -> Bold from the LLM when it validates.

Kept free of audio and models so it can be tested on hand-written notes.
"""

from app import llm
from app.harmoniser import harmonise
from app.harmoniser.prior import load_prior
from app.melody import classify_input, detect_melody_key, extract_melody
from app.onset import trim_notes
from app.timing import BeatGrid, estimate_grid, grid_from_click

_ROUTE_NOTES = {
    "melody": None,
    "polyphonic": "This sounds like chords on one instrument. Suggestions follow its top line for now.",
    "full_mix": "This sounds like a full song. Suggestions follow its top line for now; "
    "recognising the song's own chords comes next.",
}


def suggest(
    melody: list[dict],
    grid: BeatGrid,
    key: dict | None = None,
    per_bar: int = 1,
    use_llm: bool = True,
) -> dict:
    """Grid, key, progressions and insight for a melody. Also what
    /harmonise returns when the user nudges the grid or the key."""
    if not melody:
        return {"grid": None, "key": None, "progressions": [], "insight": None}
    key = key or detect_melody_key(melody, grid)
    result = harmonise(melody, grid, key, per_bar)
    progressions = result["progressions"]
    if use_llm and progressions:
        bold = llm.bold_progression(result["_slots"], result["_key"], load_prior(), result["_picked"], llm.gemini_client())
        if bold is not None:
            progressions = [p for p in progressions if p["kind"] != "bold"] + [bold]
    start = min(n["start_time"] for n in melody)
    end = max(n["end_time"] for n in melody)
    return {
        "grid": grid.to_dict(min(start, grid.downbeat), end),
        "key": key,
        "progressions": progressions,
        "insight": result["insight"],
    }


def analyze_notes(
    notes: list[dict],
    bpm: float | None = None,
    first_beat: float | None = None,
    meter: int | None = None,
    use_llm: bool = True,
    percussive: float = 0.0,
    music_start: float = 0.0,
) -> dict:
    # Notes Basic Pitch "heard" in a silent lead-in are hum and handling
    # noise; left in, they become the melody's first note and pull the
    # grid and the first chord back into the silence.
    notes = trim_notes(notes, music_start)
    route = classify_input(notes, percussive)
    melody = extract_melody(notes)
    if bpm and first_beat is not None:
        grid = grid_from_click(bpm, first_beat, meter or 4)
    else:
        grid = estimate_grid(melody, meter)
    return {
        "notes": notes,
        "route": route,
        "route_note": _ROUTE_NOTES[route],
        "melody": melody,
        "music_start": round(music_start, 3),
        **suggest(melody, grid, per_bar=1, use_llm=use_llm),
    }
