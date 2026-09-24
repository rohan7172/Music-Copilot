"""MIDI pitch <-> note name conversion."""

_NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def midi_to_note_name(midi_pitch: int) -> str:
    """Convert a MIDI pitch number (0-127) to a note name + octave, e.g. 60 -> 'C4'."""
    octave = midi_pitch // 12 - 1
    name = _NOTE_NAMES[midi_pitch % 12]
    return f"{name}{octave}"
