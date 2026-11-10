"""The Bold progression: an LLM proposes it, the theory engine decides.

1. Gemini gets a compact, factual summary of the melody (key, notes per
   bar with their beat weight, phrase ends, the Safe and Colourful picks)
   and proposes adventurous progressions in Roman numerals.
2. Every proposal is parsed into the engine's chord vocabulary and scored
   on the same terms as the other progressions; any chord that clashes
   with a long or strong-beat melody note gets the proposal rejected.
3. Gemini then writes the "why" for the winner, given only the engine's
   facts about each chord, so the explanation can't invent music theory
   the melody doesn't support.

If there's no API key, the call fails, or nothing survives validation, the
caller keeps the corpus "surprising" option. Only the symbolic summary is
ever sent, never audio.
"""

import hashlib
import json
import os
import urllib.error
import urllib.request
from collections.abc import Callable

from app.harmoniser import describe_path, scoring
from app.harmoniser.search import COLOURFUL, Path, differs, score_fixed
from app.harmoniser.vocab import Key, parse_roman

Client = Callable[[str], dict | None]

_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
_TIMEOUT = 8.0
_cache: dict[str, dict | None] = {}


def gemini_client() -> Client | None:
    """A callable that sends a prompt to Gemini and returns its JSON reply,
    or None when no API key is configured."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return None
    model = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")

    def call(prompt: str) -> dict | None:
        body = json.dumps(
            {
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {"responseMimeType": "application/json", "temperature": 0.9},
            }
        ).encode()
        request = urllib.request.Request(
            _URL.format(model=model),
            data=body,
            headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        )
        try:
            with urllib.request.urlopen(request, timeout=_TIMEOUT) as response:
                reply = json.loads(response.read())
            text = reply["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(text)
        except (urllib.error.URLError, TimeoutError, KeyError, IndexError, ValueError) as e:
            print(f"Gemini call failed: {e}")
            return None

    return call


def _note_name(key: Key, midi: int) -> str:
    return key.name_of(midi % 12)


def melody_summary(slots: list[scoring.Slot], key: Key) -> str:
    lines = []
    for slot in slots:
        if slot.empty:
            lines.append(f"Bar {slot.index + 1}: rest")
            continue
        parts = []
        for n in slot.notes:
            beat = "strong" if n.strength >= 0.75 else "weak"
            parts.append(f"{_note_name(key, n.midi)} ({beat} beat, {n.beats:.1f} beats)")
        end = " — phrase ends" if slot.phrase_end else ""
        lines.append(f"Bar {slot.index + 1}: {', '.join(parts)}{end}")
    return "\n".join(lines)


def _propose_prompt(summary: str, key: Key, n: int, safe: list[str], colourful: list[str]) -> str:
    key_name = f"{key.name_of(key.tonic)} {key.mode}"
    return f"""You are an inventive songwriter and arranger. A user hummed a melody in {key_name}.
Here it is, bar by bar (one chord per bar):

{summary}

A plain harmonisation is: {' '.join(safe)}
A richer one is: {' '.join(colourful) if colourful else '(none)'}

Propose 3 different progressions that are more adventurous and exciting than those, but that a
musician would still call beautiful over this exact melody. Use borrowed chords, secondary
dominants, chromatic mediants, deceptive moves or modal colour where they suit the tune.
Keep long and strong-beat melody notes inside (or as rich tensions of) each chord.

Rules:
- Exactly {n} chords per progression, one per bar.
- Write each chord as a Roman numeral relative to {key_name}: e.g. I, ii7, IVmaj7, V7, vi, bVI,
  bVII, iv, bIII, V7/vi, V/V, viiø7, Isus4. Use b for flat. No inversions, no slash bass notes.
- Start and end on a tonic-function chord.

Reply as JSON: {{"progressions": [{{"chords": ["I", ...], "idea": "<one short phrase>"}}]}}"""


def _explain_prompt(key: Key, facts: list[dict], idea: str) -> str:
    key_name = f"{key.name_of(key.tonic)} {key.mode}"
    return f"""You are a warm, curious music companion explaining a chord progression to a learner.
The melody is in {key_name}. The progression's idea: "{idea}".

Here are verified facts about each chord against the user's melody. Use ONLY these facts; do not
invent notes, intervals or theory that aren't listed.

{json.dumps(facts, indent=1)}

Write:
- "character": the progression's mood in 3 to 7 words (e.g. "dreamy, with a dark twist").
- "chords": one entry per chord, in order, each {{"why": "<one sentence, at most 22 words, plain words, refer to the user's notes>"}}.

Reply as JSON: {{"character": "...", "chords": [{{"why": "..."}}]}}"""


def _facts(path: Path, slots, key: Key, prior) -> list[dict]:
    out = []
    for step, slot in zip(path.steps, slots):
        c = step.chord
        notes = {"chord_tones": [], "colour_tones": [], "passing": [], "clashes": []}
        bucket = {scoring.TONE: "chord_tones", scoring.COLOUR: "colour_tones", scoring.PASSING: "passing", scoring.CLASH: "clashes"}
        for n in slot.notes:
            kind = scoring.classify(n, c)
            label = _note_name(key, n.midi)
            if kind == scoring.COLOUR:
                label += f" (the {scoring.interval_name(n.pc, c)})"
            notes[bucket[kind]].append(label)
        out.append(
            {
                "bar": slot.index + 1,
                "chord": c.symbol(key),
                "roman": c.roman,
                "function": c.function,
                "kind": c.kind,
                "how_common_in_songs": f"{100 * prior.share(key.mode, c.token(key)):.1f}% of chords",
                **{k: v for k, v in notes.items() if v},
                **({"phrase_end": True} if slot.phrase_end else {}),
            }
        )
    return out


def _valid(proposal: object, slots, key: Key) -> list | None:
    if not isinstance(proposal, dict) or not isinstance(proposal.get("chords"), list):
        return None
    chords = [parse_roman(str(t), key) for t in proposal["chords"]]
    if len(chords) != len(slots) or any(c is None for c in chords):
        return None
    if any(scoring.has_strong_clash(c, slot) for c, slot in zip(chords, slots)):
        return None
    return chords


def bold_progression(slots, key: Key, prior, picked: dict, client: Client | None) -> dict | None:
    """The validated LLM progression as an API dict (kind "bold", source
    "llm"), or None so the caller keeps the corpus option."""
    if client is None or not slots or picked.get("safe") is None:
        return None
    safe = list(picked["safe"].chords)
    colourful = list(picked["colourful"].chords) if picked.get("colourful") else []
    summary = melody_summary(slots, key)
    cache_key = hashlib.sha256(
        (summary + key.name_of(key.tonic) + key.mode + str([c.roman for c in safe])).encode()
    ).hexdigest()
    if cache_key in _cache:
        return _cache[cache_key]

    result = None
    try:
        reply = client(_propose_prompt(summary, key, len(slots), [c.roman for c in safe], [c.roman for c in colourful]))
        candidates = []
        for proposal in (reply or {}).get("progressions", []) if isinstance(reply, dict) else []:
            chords = _valid(proposal, slots, key)
            if chords is None:
                continue
            if differs(tuple(chords), tuple(safe)) == 0 or (colourful and differs(tuple(chords), tuple(colourful)) == 0):
                continue
            path = score_fixed(slots, key, prior, chords, COLOURFUL)
            candidates.append((path, str(proposal.get("idea", "")).strip()))
        if candidates:
            path, idea = max(candidates, key=lambda c: c[0].score)
            described = describe_path("bold", path, slots, key, source="llm")
            explanation = client(_explain_prompt(key, _facts(path, slots, key, prior), idea))
            whys = explanation.get("chords") if isinstance(explanation, dict) else None
            if isinstance(whys, list) and len(whys) == len(described["chords"]):
                for chord, why in zip(described["chords"], whys):
                    text = str(why.get("why", "")).strip() if isinstance(why, dict) else ""
                    if text:
                        chord["reasons"] = [text] + chord["reasons"][:1]
            character = explanation.get("character") if isinstance(explanation, dict) else None
            described["character"] = str(character).strip() if character else (idea or described["character"])
            result = described
    except Exception as e:  # never let the LLM break an analysis
        print(f"Bold progression failed: {e}")
        result = None
    _cache[cache_key] = result
    return result


__all__ = ["bold_progression", "gemini_client", "melody_summary"]
