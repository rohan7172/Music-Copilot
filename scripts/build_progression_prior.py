"""Builds backend/app/data/progression_prior.json from the Chordonomicon
chord corpus (~680k songs, CC BY-NC 4.0: fine for this personal project,
must be replaced before any commercial use).

Each song section's chords are turned into key-relative tokens ("7:7" is
V7 in any key) and counted as unigrams, bigrams and trigrams per mode.
The key of each section is estimated Krumhansl-style from its chord tones,
nudged toward the whole song's key so short sections stay stable.

Usage (from the repo root, with the CSV downloaded to backend/data_raw/):
    backend/venv/bin/python scripts/build_progression_prior.py
"""

import collections
import csv
import json
import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "backend" / "data_raw" / "chordonomicon_v2.csv"
TARGET = ROOT / "backend" / "app" / "data" / "progression_prior.json"

_LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Corpus quality spellings collapsed onto the harmoniser's vocabulary.
_QUALITY = {
    "": "maj", "min": "min", "7": "7", "min7": "m7", "maj7": "maj7",
    "sus4": "sus4", "sus2": "sus2", "7sus4": "sus4", "7sus2": "sus2",
    "maj7sus2": "sus2", "maj7sus4": "sus4",
    "add9": "maj", "add13": "maj", "add11": "maj", "6": "maj",
    "dim": "dim", "dim7": "dim", "hdim7": "m7b5", "min7b5": "m7b5", "m7b5": "m7b5",
    "aug": "aug", "augmaj7": "aug", "augmaj9": "aug",
    "9": "7", "11": "7", "13": "7", "7b9": "7", "13b": "7",
    "min9": "m7", "min11": "m7", "min13": "m7",
    "minadd13": "min", "minadd9": "min", "minadd11": "min", "minmaj7": "min", "minb9": "min",
    "min6": "min",
    "maj9": "maj7", "maj13": "maj7", "maj11": "maj7", "majs9": "maj7", "maj911s": "maj7",
}
_TONES = {
    "maj": (0, 4, 7), "min": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10),
    "maj7": (0, 4, 7, 11), "dim": (0, 3, 6), "m7b5": (0, 3, 6, 10), "aug": (0, 4, 8),
    "sus4": (0, 5, 7), "sus2": (0, 2, 7),
}

# Krumhansl-Kessler key profiles.
_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
_PROFILES = np.array(
    [np.roll(_MAJOR, k) for k in range(12)] + [np.roll(_MINOR, k) for k in range(12)]
)
_PROFILES = (_PROFILES - _PROFILES.mean(axis=1, keepdims=True)) / _PROFILES.std(axis=1, keepdims=True)

_CHORD_RE = re.compile(r"^([A-G])(s(?!us)|b)?(.*)$")


def parse_chord(token: str) -> tuple[int, str] | None:
    """(root pitch class, quality) for a corpus chord like 'Fsmin7/A', or
    None for anything outside the vocabulary (e.g. power chords)."""
    m = _CHORD_RE.match(token)
    if not m:
        return None
    root = _LETTERS[m.group(1)] + {"s": 1, "b": -1, None: 0}[m.group(2)]
    rest = m.group(3).split("/")[0]
    if rest.startswith("us"):  # 'Csus4': the 's' was the start of 'sus'
        rest = "s" + rest
    quality = _QUALITY.get(rest)
    if quality is None:
        return None
    return root % 12, quality


def histogram(chords: list[tuple[int, str]]) -> np.ndarray:
    h = np.zeros(12)
    for root, quality in chords:
        for i in _TONES[quality]:
            h[(root + i) % 12] += 1.0
        h[root] += 0.5
    return h


def estimate_key(h: np.ndarray) -> tuple[int, str]:
    if h.sum() == 0:
        return 0, "major"
    z = (h - h.mean()) / (h.std() or 1)
    best = int(np.argmax(_PROFILES @ z))
    return best % 12, ("major" if best < 12 else "minor")


def sections(chord_field: str) -> list[list[tuple[int, str]]]:
    out, current = [], []
    for token in chord_field.split():
        if token.startswith("<"):
            if current:
                out.append(current)
            current = []
            continue
        parsed = parse_chord(token)
        if parsed is None:
            if current:
                out.append(current)
            current = []
            continue
        if not current or current[-1] != parsed:  # held chords aren't moves
            current.append(parsed)
    if current:
        out.append(current)
    return out


def main(limit: int | None = None) -> None:
    csv.field_size_limit(10**8)
    counts = {
        mode: {"unigram": collections.Counter(), "bigram": collections.Counter(), "trigram": collections.Counter()}
        for mode in ("major", "minor")
    }
    songs = 0
    with SOURCE.open() as f:
        for row in csv.DictReader(f):
            secs = sections(row["chords"])
            if not secs:
                continue
            song_h = histogram([c for s in secs for c in s])
            song_h = song_h / max(song_h.sum(), 1)
            for sec in secs:
                h = histogram(sec)
                tonic, mode = estimate_key(h / max(h.sum(), 1) + 0.6 * song_h)
                tokens = [f"{(root - tonic) % 12}:{quality}" for root, quality in sec]
                table = counts[mode]
                table["unigram"].update(tokens)
                table["bigram"].update(f"{a}|{b}" for a, b in zip(tokens, tokens[1:]))
                table["trigram"].update(f"{a}|{b}|{c}" for a, b, c in zip(tokens, tokens[1:], tokens[2:]))
            songs += 1
            if songs % 50000 == 0:
                print(f"{songs} songs", file=sys.stderr)
            if limit and songs >= limit:
                break

    modes = {}
    for mode, table in counts.items():
        modes[mode] = {
            "unigram": dict(table["unigram"]),
            "bigram": {k: v for k, v in table["bigram"].items() if v >= 5},
            "trigram": {k: v for k, v in table["trigram"].items() if v >= 25},
        }
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(
        json.dumps(
            {
                "source": "corpus",
                "corpus": "Chordonomicon v2 (CC BY-NC 4.0)",
                "songs": songs,
                "modes": modes,
            },
            separators=(",", ":"),
        )
    )
    size = TARGET.stat().st_size / 1e6
    print(f"{songs} songs -> {TARGET} ({size:.1f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else None)
