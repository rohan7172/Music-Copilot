from app import llm
from app.harmoniser import harmonise
from app.harmoniser.prior import load_prior
from app.timing import BeatGrid
from tests.melodies import TWINKLE, notes

GRID = BeatGrid(bpm=100, downbeat=0.0)


def _setup():
    llm._cache.clear()
    result = harmonise(notes(TWINKLE), GRID, {"tonic": "C", "mode": "major"})
    return result["_slots"], result["_key"], result["_picked"]


def _stub(proposals, explanation=None):
    calls = []

    def client(prompt):
        calls.append(prompt)
        if len(calls) == 1:
            return proposals
        return explanation

    client.calls = calls
    return client


# Fits the melody throughout: C7 (V7/IV) under "D D C" and Em under "E E D" are the turns.
GOOD = "I vi IVmaj7 V7/IV V7 iii V7 V I vi IVmaj7 I".split()


def test_a_valid_proposal_becomes_bold_with_llm_reasons():
    slots, key, picked = _setup()
    whys = [{"why": f"bar {i} reason"} for i in range(len(slots))]
    client = _stub(
        {"progressions": [{"chords": GOOD, "idea": "a dark twist"}]},
        {"character": "dreamy with a dark twist", "chords": whys},
    )
    bold = llm.bold_progression(slots, key, load_prior(), picked, client)
    assert bold is not None
    assert bold["source"] == "llm"
    assert bold["character"] == "dreamy with a dark twist"
    assert bold["chords"][3]["symbol"] == "C7"
    assert bold["chords"][0]["reasons"][0] == "bar 0 reason"
    # The explanation prompt carries the engine's facts about the melody.
    assert "chord_tones" in client.calls[1]


def test_a_clashing_proposal_is_rejected():
    slots, key, picked = _setup()
    # bII under bar 1's long C and G clashes on strong beats.
    clashing = ["bII"] + GOOD[1:]
    client = _stub({"progressions": [{"chords": clashing, "idea": "x"}]})
    assert llm.bold_progression(slots, key, load_prior(), picked, client) is None


def test_garbage_or_wrong_length_falls_back():
    slots, key, picked = _setup()
    for reply in (None, {"progressions": "nope"}, {"progressions": [{"chords": ["I", "V"]}]},
                  {"progressions": [{"chords": ["Q"] * len(slots)}]}):
        llm._cache.clear()
        assert llm.bold_progression(slots, key, load_prior(), picked, _stub(reply)) is None


def test_no_client_means_no_llm_call():
    slots, key, picked = _setup()
    assert llm.bold_progression(slots, key, load_prior(), picked, None) is None


def test_a_failing_explanation_keeps_template_reasons():
    slots, key, picked = _setup()
    client = _stub({"progressions": [{"chords": GOOD, "idea": "a dark twist"}]}, None)
    bold = llm.bold_progression(slots, key, load_prior(), picked, client)
    assert bold is not None
    assert bold["character"] == "a dark twist"
    assert all(c["reasons"] for c in bold["chords"])


def test_summary_marks_strong_beats_and_phrase_ends():
    slots, key, _ = _setup()
    summary = llm.melody_summary(slots, key)
    assert summary.startswith("Bar 1: C (strong beat")
    assert "phrase ends" in summary
