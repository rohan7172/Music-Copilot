"""The chords the harmoniser may choose from in a key, and how to name them.

Each candidate is tagged by how far it sits from the plain key, which is
what the key-fit cost and the "why" text are built on:

- diatonic:  the key's own triads (I, ii, iii, IV, V, vi, vii° in major)
- seventh:   the same chords with a seventh added (colour, still in key)
- sus:       a suspended chord (no third; open, unresolved)
- secondary: a "dominant of" another chord (V/V, V/vi...), leaning into it
- borrowed:  a chord from the parallel key (♭VI, ♭VII, iv in major)
- chromatic: anything else (only reachable via an LLM suggestion)
"""

import re
from dataclasses import dataclass

QUALITIES: dict[str, tuple[int, ...]] = {
    "maj": (0, 4, 7),
    "min": (0, 3, 7),
    "dim": (0, 3, 6),
    "aug": (0, 4, 8),
    "7": (0, 4, 7, 10),
    "maj7": (0, 4, 7, 11),
    "m7": (0, 3, 7, 10),
    "m7b5": (0, 3, 6, 10),
    "sus4": (0, 5, 7),
    "sus2": (0, 2, 7),
}

_SYMBOL_SUFFIX = {
    "maj": "", "min": "m", "dim": "dim", "aug": "aug", "7": "7",
    "maj7": "maj7", "m7": "m7", "m7b5": "m7b5", "sus4": "sus4", "sus2": "sus2",
}

KEY_COST = {
    "diatonic": 0.0,
    "seventh": 0.12,
    "sus": 0.5,
    "secondary": 0.45,
    "borrowed": 0.55,
    "chromatic": 0.9,
}

SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
_FLAT_MAJOR_PCS = {5, 10, 3, 8, 1}  # F, Bb, Eb, Ab, Db major
_FLAT_MINOR_PCS = {2, 7, 0, 5, 10, 3}  # D, G, C, F, Bb, Eb minor

_NAME_TO_PC = {**{n: i for i, n in enumerate(SHARP_NAMES)}, **{n: i for i, n in enumerate(FLAT_NAMES)}}


def pc_of(name: str) -> int:
    return _NAME_TO_PC[name.replace("-", "b")]


@dataclass(frozen=True)
class Key:
    tonic: int  # pitch class
    mode: str  # "major" | "minor"

    @property
    def names(self) -> list[str]:
        """Note names spelled the way this key's signature does: flats for
        F, Bb, Eb, Ab, Db major (and D, G, C, F, Bb minor), sharps otherwise.
        F# major and the minor keys on C#, F#, G# and D# use sharps, as
        they're conventionally written."""
        flat_keys = _FLAT_MAJOR_PCS if self.mode == "major" else _FLAT_MINOR_PCS
        return FLAT_NAMES if self.tonic in flat_keys else SHARP_NAMES

    def name_of(self, pc: int) -> str:
        return self.names[pc % 12]

    @staticmethod
    def from_dict(d: dict) -> "Key":
        return Key(tonic=pc_of(d["tonic"]), mode=d["mode"])


@dataclass(frozen=True)
class Chord:
    root: int
    quality: str
    roman: str
    kind: str
    function: str  # "tonic" | "predominant" | "dominant"

    @property
    def pcs(self) -> frozenset[int]:
        return frozenset((self.root + i) % 12 for i in QUALITIES[self.quality])

    def root_name(self, key: Key) -> str:
        # A flattened degree is spelled with a flat (A♭ in C major, not G#).
        names = key.names
        if self.roman.startswith("♭"):
            names = FLAT_NAMES
        elif self.roman.startswith("♯"):
            names = SHARP_NAMES
        return names[self.root % 12]

    def symbol(self, key: Key) -> str:
        return self.root_name(key) + _SYMBOL_SUFFIX[self.quality]

    def token(self, key: Key) -> str:
        """Key-relative identity used by the corpus prior: semitones above
        the tonic plus quality, e.g. "7:7" for V7 in any key."""
        return f"{(self.root - key.tonic) % 12}:{self.quality}"

    @property
    def is_colour(self) -> bool:
        return self.kind != "diatonic"


# Diatonic triads and sevenths: (semitones above tonic, triad, seventh).
_MAJOR = [(0, "maj", "maj7"), (2, "min", "m7"), (4, "min", "m7"), (5, "maj", "maj7"),
          (7, "maj", "7"), (9, "min", "m7"), (11, "dim", "m7b5")]
_MINOR = [(0, "min", "m7"), (2, "dim", "m7b5"), (3, "maj", "maj7"), (5, "min", "m7"),
          (7, "min", "m7"), (8, "maj", "maj7"), (10, "maj", "7")]

_FUNCTIONS = {
    "major": {0: "tonic", 2: "predominant", 4: "tonic", 5: "predominant", 7: "dominant",
              9: "tonic", 11: "dominant", 8: "predominant", 10: "predominant", 3: "tonic",
              1: "predominant", 6: "predominant"},
    "minor": {0: "tonic", 2: "predominant", 3: "tonic", 5: "predominant", 7: "dominant",
              8: "tonic", 10: "dominant", 11: "dominant", 1: "predominant", 9: "predominant",
              4: "tonic", 6: "predominant"},
}

# Scale-degree numerals by semitones above the tonic, per mode.
_DEGREE_NAME = {
    "major": {0: "I", 1: "♭II", 2: "II", 3: "♭III", 4: "III", 5: "IV", 6: "♯IV",
              7: "V", 8: "♭VI", 9: "VI", 10: "♭VII", 11: "VII"},
    "minor": {0: "I", 1: "♭II", 2: "II", 3: "III", 4: "♯III", 5: "IV", 6: "♯IV",
              7: "V", 8: "VI", 9: "♯VI", 10: "VII", 11: "♯VII"},
}


def roman_for(interval: int, quality: str, mode: str) -> str:
    numeral = _DEGREE_NAME[mode][interval % 12]
    if mode == "minor" and interval % 12 == 11 and quality in ("dim", "m7b5"):
        numeral = "VII"  # vii° in minor is the leading-tone chord, written plain
    lower = quality in ("min", "dim", "m7", "m7b5")
    head = numeral.lower() if lower else numeral
    suffix = {"maj": "", "min": "", "dim": "°", "aug": "+", "7": "7", "maj7": "maj7",
              "m7": "7", "m7b5": "ø7", "sus4": "sus4", "sus2": "sus2"}[quality]
    return head + suffix


def _chord(key: Key, interval: int, quality: str, kind: str, roman: str | None = None) -> Chord:
    return Chord(
        root=(key.tonic + interval) % 12,
        quality=quality,
        roman=roman or roman_for(interval, quality, key.mode),
        kind=kind,
        # A secondary dominant is a dominant, aimed at a chord other than I.
        function="dominant" if kind == "secondary" else _FUNCTIONS[key.mode][interval % 12],
    )


def vocabulary(key: Key) -> list[Chord]:
    """Every candidate chord in the key, most ordinary first."""
    out: list[Chord] = []
    scale = _MAJOR if key.mode == "major" else _MINOR
    for interval, triad, seventh in scale:
        out.append(_chord(key, interval, triad, "diatonic"))
    if key.mode == "minor":
        # The harmonic-minor dominant: major V and V7, and the leading-tone vii°,
        # are how minor keys normally cadence.
        out.append(_chord(key, 7, "maj", "diatonic"))
        out.append(_chord(key, 11, "dim", "diatonic"))
    for interval, _, seventh in scale:
        out.append(_chord(key, interval, seventh, "seventh"))
    if key.mode == "minor":
        out.append(_chord(key, 7, "7", "seventh"))

    out.append(_chord(key, 0, "sus4", "sus"))
    out.append(_chord(key, 7, "sus4", "sus"))
    out.append(_chord(key, 0, "sus2", "sus"))

    if key.mode == "major":
        secondaries = [(2, "V/V"), (4, "V/vi"), (9, "V/ii"), (0, "V/IV")]
    else:
        secondaries = [(0, "V/iv"), (3, "V/VI"), (2, "V/V")]
    for interval, label in secondaries:
        if interval != 0:
            out.append(_chord(key, interval, "maj", "secondary", label))
        out.append(_chord(key, interval, "7", "secondary", label.replace("V/", "V7/", 1)))

    if key.mode == "major":
        borrowed = [(8, "maj"), (10, "maj"), (5, "min"), (3, "maj"), (5, "m7")]
    else:
        borrowed = [(5, "maj"), (0, "maj"), (1, "maj")]
    for interval, quality in borrowed:
        out.append(_chord(key, interval, quality, "borrowed"))

    seen: set[tuple[int, str]] = set()
    unique = []
    for c in out:
        if (c.root, c.quality) not in seen:
            seen.add((c.root, c.quality))
            unique.append(c)
    return unique


_ROMAN_RE = re.compile(
    r"^(?P<acc>[b#]?)(?P<num>VII|VI|IV|V|III|II|I|vii|vi|iv|v|iii|ii|i)"
    r"(?P<qual>°7|ø7|o7|°|ø|o|\+|maj7|M7|Δ7|Δ|m7b5|7|sus4|sus2|add9|9)?"
    r"(?P<inv>6|64|65|43|42)?$"
)
_NUMERALS = {"I": 0, "II": 2, "III": 4, "IV": 5, "V": 7, "VI": 9, "VII": 11}
_MINOR_NUMERALS = {"I": 0, "II": 2, "III": 3, "IV": 5, "V": 7, "VI": 8, "VII": 10}


def _parse_single(token: str, mode: str) -> tuple[int, str] | None:
    m = _ROMAN_RE.match(token)
    if not m:
        return None
    num = m.group("num")
    upper = num.upper()
    qual = m.group("qual") or ""
    interval = (_MINOR_NUMERALS if mode == "minor" else _NUMERALS)[upper]
    if mode == "minor" and upper == "VII" and qual in ("°", "o", "°7", "o7", "ø", "ø7"):
        interval = 11
    if m.group("acc") == "b":
        interval = (_NUMERALS[upper] - 1) % 12
    elif m.group("acc") == "#":
        interval = (_NUMERALS[upper] + 1) % 12 if mode == "major" else (interval + 1) % 12
    if qual in ("°", "o", "°7", "o7"):
        quality = "dim"
    elif qual in ("ø", "ø7", "m7b5"):
        quality = "m7b5"
    elif qual == "+":
        quality = "aug"
    elif qual in ("maj7", "M7", "Δ", "Δ7"):
        quality = "maj7"
    elif qual in ("sus4", "sus2"):
        quality = qual
    elif qual in ("7", "9"):
        quality = "7" if num.isupper() else "m7"
    else:
        quality = "maj" if num.isupper() else "min"
    return interval, quality


def parse_roman(text: str, key: Key) -> Chord | None:
    """A Roman numeral like "V7/vi", "♭VI", "ii7", "IVmaj7" or "vii°" as a
    chord in the key, or None if it can't be read. Chords outside the
    vocabulary are still returned, tagged "chromatic"."""
    token = text.strip().replace("♭", "b").replace("♯", "#").replace(" ", "")
    if not token:
        return None
    if "/" in token:
        head, _, target = token.partition("/")
        target_parsed = _parse_single(target, key.mode)
        head_parsed = _parse_single(head, "major")
        if not target_parsed or not head_parsed:
            return None
        interval = (target_parsed[0] + head_parsed[0]) % 12
        quality = head_parsed[1]
    else:
        parsed = _parse_single(token, key.mode)
        if not parsed:
            return None
        interval, quality = parsed
    root = (key.tonic + interval) % 12
    for c in vocabulary(key):
        if c.root == root and c.quality == quality:
            return c
    return _chord(key, interval, quality, "chromatic")


def chord_in_key(root: int, quality: str, key: Key) -> Chord:
    """The vocabulary's chord for this root and quality in the key (with its
    Roman numeral, kind and function), or a "chromatic" one if it isn't in
    the vocabulary. Used for chords recognised in a song."""
    for c in vocabulary(key):
        if c.root == root % 12 and c.quality == quality:
            return c
    return _chord(key, (root - key.tonic) % 12, quality, "chromatic")
