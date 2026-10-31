"""What each instrument in a song is doing, in plain words.

Instead of one wall of every note, a song is shown as parts — melody,
bass, harmony, drums — each with the notes it plays and one or two
sentences about its role, measured against the recognised chords and the
beat. Pure functions over notes, chord spans and beat times, so each
claim is checkable and tested without any model.
"""

import numpy as np

from app.harmoniser.vocab import QUALITIES


def _chord_at(t: float, chords: list[dict]) -> dict | None:
    for c in chords:
        if c["start"] <= t < c["end"]:
            return c
    return None


def _pcs(chord: dict) -> set[int]:
    root, quality = chord["state"]
    return {(root + i) % 12 for i in QUALITIES[quality]}


def melody_role(melody: list[dict], chords: list[dict]) -> dict:
    """How the tune sits on the chords: the share of its time spent on
    chord tones (what makes a melody sound "inside" the harmony)."""
    on, total = 0.0, 0.0
    for n in melody:
        c = _chord_at(n["start_time"], chords)
        if c is None:
            continue
        length = n["end_time"] - n["start_time"]
        total += length
        if n["midi_pitch"] % 12 in _pcs(c):
            on += length
    if total <= 0:
        return {"summary": "The sung melody.", "detail": None}
    share = round(100 * on / total)
    if share >= 70:
        feel = "so it sits right inside the harmony"
    elif share >= 45:
        feel = "the rest are passing and colour notes that give it movement"
    else:
        feel = "it floats over the chords, leaning on colour notes and tension"
    # The range a listener hears: 5th to 95th percentile, so a few stray
    # notes leaking into the vocal stem don't stretch it.
    pitches = [n["midi_pitch"] for n in melody]
    low, high = (int(round(v)) for v in np.percentile(pitches, [5, 95]))
    return {
        "summary": f"The tune. It lands on notes of the chord {share}% of the time: {feel}.",
        "detail": f"It spans {high - low} semitones" + (", a wide, soaring range." if high - low >= 15 else "."),
        "chord_tone_share": share,
    }


def bass_role(bass: list[dict], chords: list[dict], downbeats: list[float]) -> dict:
    """How often the bass plays the chord's root on a bar's first beat:
    the bass is usually what tells your ear which chord you're on."""
    hits, counted = 0, 0
    for d in downbeats:
        c = _chord_at(d + 0.02, chords)
        sounding = [n for n in bass if n["start_time"] - 0.12 <= d < n["end_time"]]
        if c is None or not sounding:
            continue
        counted += 1
        lowest = min(sounding, key=lambda n: n["midi_pitch"])
        if lowest["midi_pitch"] % 12 == c["state"][0]:
            hits += 1
    if counted == 0 or not bass:
        return {"summary": "The low end under the chords.", "detail": None}
    share = round(100 * hits / counted)
    notes_per_bar = len(bass) / max(len(downbeats), 1)
    if share >= 65:
        summary = (
            f"Plays the chord's root on {share}% of bar starts: it's what tells "
            "your ear which chord you're on."
        )
    else:
        summary = (
            f"Plays the root on only {share}% of bar starts, so it walks between "
            "chord tones (inversions, passing notes) instead of just anchoring."
        )
    motion = "a busy, moving line" if notes_per_bar >= 6 else "a steady, simple line" if notes_per_bar <= 2.5 else "a line that moves a little in each bar"
    return {"summary": summary, "detail": f"About {notes_per_bar:.0f} notes a bar: {motion}.", "root_share": share}


def harmony_style(notes: list[dict]) -> str:
    """'strummed' (notes start together: block chords), 'arpeggiated'
    (one after another), or 'sustained' (few long notes: pads)."""
    if len(notes) < 4:
        return "sustained"
    onsets = sorted(n["start_time"] for n in notes)
    groups, current = [], [onsets[0]]
    for t in onsets[1:]:
        if t - current[0] <= 0.05:
            current.append(t)
        else:
            groups.append(current)
            current = [t]
    groups.append(current)
    together = sum(len(g) for g in groups if len(g) >= 3) / len(onsets)
    mean_length = float(np.mean([n["end_time"] - n["start_time"] for n in notes]))
    span = onsets[-1] - onsets[0] or 1.0
    attacks_per_second = len(groups) / span
    if together >= 0.5:
        return "strummed"
    if mean_length >= 1.2 and attacks_per_second < 1.5:
        return "sustained"
    return "arpeggiated"


def harmony_role(notes: list[dict]) -> dict:
    style = harmony_style(notes)
    summary = {
        "strummed": "Guitars or keys playing block chords: several notes struck together, filling out the harmony.",
        "arpeggiated": "Guitars or keys picking the chords one note at a time (arpeggios), giving the harmony a flowing motion.",
        "sustained": "Long held chords (pads or sustained keys): a soft bed of harmony under everything.",
    }[style]
    return {"summary": summary, "detail": None, "style": style}


def drums_role(onsets: list[float], beats: list[float], downbeats: list[float], strengths: list[float] | None = None, meter: int = 4) -> dict:
    """How busy the drums are and where they accent: a backbeat (hits
    loudest on 2 and 4) is the classic pop and rock feel."""
    if not onsets or len(downbeats) < 2:
        return {"summary": "Keeps time.", "detail": None}
    bars = max(len(downbeats) - 1, 1)
    span = (downbeats[0], downbeats[-1])
    inside = [t for t in onsets if span[0] <= t < span[1]]
    per_bar = len(inside) / bars
    busy = "a busy, driving pattern" if per_bar >= 10 else "a steady pattern" if per_bar >= 5 else "a sparse, laid-back pattern"
    summary = f"Keeps time with about {per_bar:.0f} hits a bar: {busy}."
    detail = None
    if strengths is not None and meter == 4 and len(beats) >= 8:
        by_position = [[] for _ in range(4)]
        beats_arr = np.asarray(beats)
        first = downbeats[0]
        for t, s in zip(onsets, strengths):
            i = int(np.argmin(np.abs(beats_arr - t)))
            if abs(beats_arr[i] - t) > 0.07:
                continue
            position = int(round((beats_arr[i] - first) / np.median(np.diff(beats_arr)))) % 4
            by_position[position].append(s)
        level = [float(np.mean(p)) if p else 0.0 for p in by_position]
        if level[1] and level[3] and min(level[1], level[3]) > 1.15 * max(level[0], level[2]):
            detail = "The loudest hits fall on beats 2 and 4: a backbeat, the classic pop and rock feel."
        elif level[0] > 1.15 * max(level[1:]):
            detail = "The strongest hit lands on beat 1 of each bar, marking where each bar begins."
    return {"summary": summary, "detail": detail, "hits_per_bar": round(per_bar, 1)}
