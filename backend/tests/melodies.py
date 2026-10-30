"""Public-domain tunes written out as notes, for harmoniser tests.

Each tune is a list of (MIDI pitch, length in beats); a pitch of None is a
rest. `notes()` turns one into the note dicts Basic Pitch would produce,
played slightly legato at a given tempo.
"""

C4, D4, E4, F4, G4, A4, B4 = 60, 62, 64, 65, 67, 69, 71
C5, D5, E5, F5 = 72, 74, 76, 77
G3 = 55

# Each bar on its own line; 4/4 unless noted.
TWINKLE = [
    (C4, 1), (C4, 1), (G4, 1), (G4, 1),
    (A4, 1), (A4, 1), (G4, 2),
    (F4, 1), (F4, 1), (E4, 1), (E4, 1),
    (D4, 1), (D4, 1), (C4, 2),
    (G4, 1), (G4, 1), (F4, 1), (F4, 1),
    (E4, 1), (E4, 1), (D4, 2),
    (G4, 1), (G4, 1), (F4, 1), (F4, 1),
    (E4, 1), (E4, 1), (D4, 2),
    (C4, 1), (C4, 1), (G4, 1), (G4, 1),
    (A4, 1), (A4, 1), (G4, 2),
    (F4, 1), (F4, 1), (E4, 1), (E4, 1),
    (D4, 1), (D4, 1), (C4, 2),
]
# Chords that a musician would accept for each bar, one chord per bar.
TWINKLE_OK = [
    {"C"}, {"F", "C", "Am"}, {"F", "Dm", "Fmaj7", "Dm7"}, {"C", "G", "G7"},
    {"G", "G7", "Dm", "Dm7"}, {"C", "G", "Em", "Am"}, {"G", "G7", "Dm", "Dm7"}, {"G", "C", "G7"},
    {"C"}, {"F", "C", "Am"}, {"F", "Dm", "Fmaj7", "Dm7"}, {"C"},
]

ODE_TO_JOY = [
    (E4, 1), (E4, 1), (F4, 1), (G4, 1),
    (G4, 1), (F4, 1), (E4, 1), (D4, 1),
    (C4, 1), (C4, 1), (D4, 1), (E4, 1),
    (E4, 1.5), (D4, 0.5), (D4, 2),
    (E4, 1), (E4, 1), (F4, 1), (G4, 1),
    (G4, 1), (F4, 1), (E4, 1), (D4, 1),
    (C4, 1), (C4, 1), (D4, 1), (E4, 1),
    (D4, 1.5), (C4, 0.5), (C4, 2),
]
ODE_TO_JOY_OK = [
    {"C", "Cmaj7"}, {"G", "G7", "Em", "C"}, {"C", "Am", "F"}, {"G", "G7", "C"},
    {"C", "Cmaj7"}, {"G", "G7", "Em", "C"}, {"C", "Am", "F"}, {"G", "C", "G7"},
]

FRERE_JACQUES = [
    (C4, 1), (D4, 1), (E4, 1), (C4, 1),
    (C4, 1), (D4, 1), (E4, 1), (C4, 1),
    (E4, 1), (F4, 1), (G4, 2),
    (E4, 1), (F4, 1), (G4, 2),
    (G4, 0.5), (A4, 0.5), (G4, 0.5), (F4, 0.5), (E4, 1), (C4, 1),
    (G4, 0.5), (A4, 0.5), (G4, 0.5), (F4, 0.5), (E4, 1), (C4, 1),
    (C4, 1), (G3, 1), (C4, 2),
    (C4, 1), (G3, 1), (C4, 2),
]
FRERE_JACQUES_OK = [{"C"}] * 8

# A minor tune (A natural minor): A C E D | C B A-.
MINOR_TUNE = [
    (A4, 1), (C5, 1), (E5, 1), (D5, 1),
    (C5, 1), (B4, 1), (A4, 2),
    (E5, 1), (D5, 1), (C5, 1), (B4, 1),
    (C5, 1), (B4, 1), (A4, 2),
]


def notes(tune, bpm=100.0, start=0.0, legato=0.92, confidence=0.8):
    beat = 60.0 / bpm
    out = []
    t = start
    for pitch, beats in tune:
        length = beats * beat
        if pitch is not None:
            out.append(
                {
                    "pitch": "",
                    "midi_pitch": pitch,
                    "start_time": round(t, 4),
                    "end_time": round(t + length * legato, 4),
                    "confidence": confidence,
                }
            )
        t += length
    return out
