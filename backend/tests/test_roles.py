from app.songs.roles import bass_role, drums_role, harmony_role, harmony_style, melody_role

C, G = (0, "maj"), (7, "maj")
CHORDS = [
    {"state": C, "start": 0.0, "end": 2.0},
    {"state": G, "start": 2.0, "end": 4.0},
]


def _n(midi, start, end):
    return {"midi_pitch": midi, "start_time": start, "end_time": end, "confidence": 0.8}


def test_melody_on_chord_tones():
    melody = [_n(64, 0.0, 1.0), _n(67, 1.0, 2.0), _n(71, 2.0, 3.0), _n(69, 3.0, 4.0)]
    role = melody_role(melody, CHORDS)
    assert role["chord_tone_share"] == 75  # E, G over C; B over G; A isn't in G
    assert "inside the harmony" in role["summary"]


def test_bass_on_roots_vs_walking():
    roots = [_n(36, 0.0, 1.9), _n(43, 2.0, 3.9)]
    assert bass_role(roots, CHORDS, [0.0, 2.0])["root_share"] == 100
    walking = [_n(40, 0.0, 1.9), _n(47, 2.0, 3.9)]  # E under C, B under G: inversions
    role = bass_role(walking, CHORDS, [0.0, 2.0])
    assert role["root_share"] == 0
    assert "walks" in role["summary"]


def test_harmony_styles():
    strummed = [_n(p, t, t + 0.4) for t in (0.0, 0.5, 1.0, 1.5) for p in (60, 64, 67)]
    assert harmony_style(strummed) == "strummed"
    arpeggio = [_n(p, i * 0.25, i * 0.25 + 0.2) for i, p in enumerate([60, 64, 67, 72] * 3)]
    assert harmony_style(arpeggio) == "arpeggiated"
    pads = [_n(60, 0.0, 4.0), _n(64, 0.02, 4.0), _n(55, 4.0, 8.0), _n(59, 4.5, 8.0)]
    assert harmony_style(pads) == "sustained"
    assert "block chords" in harmony_role(strummed)["summary"]


def test_drums_backbeat():
    beats = [i * 0.5 for i in range(17)]
    downbeats = beats[::4]
    onsets, strengths = [], []
    for i, b in enumerate(beats[:-1]):
        onsets.append(b)
        strengths.append(1.0 if i % 2 == 1 else 0.5)  # 2 and 4 loudest
        onsets.append(b + 0.25)
        strengths.append(0.3)  # eighth-note hats
    role = drums_role(onsets, beats, downbeats, strengths)
    assert role["hits_per_bar"] == 8.0
    assert "backbeat" in role["detail"]
