from app.explain import explain_progression


def chord(name, roman):
    return {"name": name, "roman": roman}


def test_no_key_or_chords_gives_a_generic_message():
    result = explain_progression(None, [])
    assert result["summary"] == "Not enough was played to make out a clear key or chord progression."
    assert result["chords"] == []


def test_each_chord_gets_its_scale_degree_role():
    key = {"name": "C major"}
    chords = [chord("C", "I"), chord("G7", "V7")]
    result = explain_progression(key, chords)
    assert result["chords"][0]["text"] == "C — the I chord, tonic: home, where the music feels at rest"
    assert result["chords"][1]["text"] == "G7 — the V7 chord, dominant: tension that pulls back toward the tonic"


def test_unrecognised_roman_numeral_falls_back_to_just_the_chord_name():
    key = {"name": "C major"}
    # An augmented-sixth label, which doesn't start with a roman numeral letter.
    chords = [chord("Abo7", "Ger6")]
    result = explain_progression(key, chords)
    assert result["chords"][0]["text"] == "Abo7"


def test_recognises_a_ii_v_i_progression():
    key = {"name": "C major"}
    chords = [chord("Dm7", "ii7"), chord("G7", "V7"), chord("Cmaj7", "I7")]
    result = explain_progression(key, chords)
    assert result["summary"] == (
        "This is in C major, moving through a ii–V–I progression — the classic "
        "jazz cadence, building tension through ii and V before resolving home."
    )


def test_recognises_an_authentic_cadence_when_no_full_pattern_matches():
    key = {"name": "G major"}
    chords = [chord("Em", "vi"), chord("D", "V"), chord("G", "I")]
    result = explain_progression(key, chords)
    assert result["summary"] == (
        "This is in G major, ending with an authentic cadence (V–I), the strongest way to resolve."
    )


def test_recognises_a_half_cadence():
    key = {"name": "C major"}
    chords = [chord("C", "I"), chord("G", "V")]
    result = explain_progression(key, chords)
    assert result["summary"] == (
        "This is in C major, ending with a half cadence — left hanging on the dominant rather than resolved."
    )


def test_falls_back_to_a_generic_summary_with_no_recognised_pattern():
    key = {"name": "C major"}
    chords = [chord("C", "I"), chord("Dm", "ii")]
    result = explain_progression(key, chords)
    assert result["summary"] == "This is in C major, moving through 2 chords."


def test_falls_back_to_singular_chord_wording_for_one_chord():
    key = {"name": "C major"}
    chords = [chord("C", "I")]
    result = explain_progression(key, chords)
    assert result["summary"] == "This is in C major, moving through 1 chord."
