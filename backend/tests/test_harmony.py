from app.harmony import analyze_harmony

C, D, E, F, G, A, B = 60, 62, 64, 65, 67, 69, 71


def note(midi, start, end, confidence=0.7):
    return {"midi_pitch": midi, "start_time": start, "end_time": end, "confidence": confidence}


def block(pitches, start, length=1.0):
    return [note(p, start, start + length) for p in pitches]


def arpeggio(pitches, start, step=0.25):
    return [note(p, start + i * step, start + (i + 1) * step) for i, p in enumerate(pitches)]


def summary(result):
    return [(c["name"], c["roman"]) for c in result["chords"]]


def test_block_chord_progression_in_c():
    # I - V - vi - IV in C major.
    notes = (
        block([C, E, G], 0)
        + block([G - 12, B - 12, D], 1)
        + block([A - 12, C, E], 2)
        + block([F - 12, A - 12, C], 3)
    )
    result = analyze_harmony(notes)
    assert result["key"]["name"] == "C major"
    assert summary(result) == [("C", "I"), ("G", "V"), ("Am", "vi"), ("F", "IV")]


def test_chord_times_follow_the_music():
    notes = block([C, E, G], 0) + block([G - 12, B - 12, D], 1)
    first, second = analyze_harmony(notes)["chords"]
    assert abs(first["start_time"] - 0) < 0.06 and abs(first["end_time"] - 1) < 0.15
    assert abs(second["start_time"] - 1) < 0.15 and abs(second["end_time"] - 2) < 0.06


def test_arpeggios_are_recognised():
    notes = arpeggio([C, E, G, C + 12], 0) + arpeggio([A - 12, C, E, A], 1)
    assert [name for name, _ in summary(analyze_harmony(notes))] == ["C", "Am"]


def test_sevenths_and_spelling_in_a_flat_key():
    # ii7 - V7 - I in F major: Gm7, C7, F. F major spells with flats (Bb).
    notes = block([G - 12, A + 1 - 12, D, F], 0) + block([C - 12, E - 12, G - 12, A + 1 - 12], 1)
    notes += block([F - 12, A - 12, C], 2, length=2.0)
    result = analyze_harmony(notes)
    assert result["key"]["name"] == "F major"
    assert summary(result) == [("Gm7", "ii7"), ("C7", "V7"), ("F", "I")]
    assert result["chords"][0]["notes"] == ["G", "Bb", "D", "F"]


def test_single_note_melody_is_not_called_a_chord():
    scale = [C, D, E, F, G, A, B, C + 12]
    notes = [note(p, i * 0.5, i * 0.5 + 0.45) for i, p in enumerate(scale)]
    result = analyze_harmony(notes)
    assert result["key"]["name"] == "C major"
    assert result["chords"] == []


def test_sus_chord_roman_numeral():
    # I - IV - Vsus4 - V - I: the sus resolving down to the plain dominant.
    notes = block([C, E, G], 0) + block([F - 12, A - 12, C], 1) + block([G - 12, C, D], 2)
    notes += block([G - 12, B - 12, D], 3) + block([C, E, G], 4)
    assert summary(analyze_harmony(notes)) == [
        ("C", "I"),
        ("F", "IV"),
        ("Gsus4", "Vsus4"),
        ("G", "V"),
        ("C", "I"),
    ]


def test_no_notes():
    assert analyze_harmony([]) == {"key": None, "chords": []}


def test_chord_survives_its_bass_fading_early():
    # Dm7 - G7 - Cmaj7 where each bass note is reported ending early, as Basic
    # Pitch tends to do. Without the bass the upper notes read as F and Bdim.
    notes = [note(50, 0, 0.4)] + block([53, 57, 60], 0)
    notes += [note(43, 1, 1.4)] + block([47, 50, 53], 1)
    notes += [note(48, 2, 2.4)] + block([52, 55, 59], 2, length=2.0)
    assert summary(analyze_harmony(notes)) == [("Dm7", "ii7"), ("G7", "V7"), ("Cmaj7", "I7")]


def test_overtone_ghosts_are_ignored():
    # A quiet note an octave and a fifth above a louder one, starting with it,
    # is Basic Pitch hearing the overtone. C-E-G plus a ghost D would be Cadd9.
    notes = block([C, E, G], 0) + [note(G + 19, 0.01, 0.4, confidence=0.3)]
    assert summary(analyze_harmony(notes)) == [("C", "I")]
