"""How likely each chord move is: P(next chord | the two before it, mode).

Learnt from a chord corpus (see scripts/build_progression_prior.py) as
counts of key-relative chord tokens ("7:7" is V7 in any key). Until that
table exists, a small rule-based stand-in models the textbook flow:
home -> away -> pull -> home.
"""

import json
import math
from functools import lru_cache
from pathlib import Path

_DATA = Path(__file__).resolve().parent.parent / "data" / "progression_prior.json"
_FLOOR = 1e-4


# The prior judges the move between chord *families* (V to I), not the
# exact quality: chord sheets in the corpus often write G7 as plain G, so
# sevenths look rarer than they're played, and whether to colour a chord
# is the melody's and the style's call, not the corpus's.
_FAMILY = {"maj": "maj", "7": "maj", "maj7": "maj", "aug": "maj", "sus4": "maj", "sus2": "maj",
           "min": "min", "m7": "min", "dim": "dim", "m7b5": "dim"}


def reduce_token(token: str) -> str:
    interval, _, quality = token.partition(":")
    return f"{interval}:{_FAMILY.get(quality, quality)}"


class ProgressionPrior:
    def __init__(self, data: dict):
        self._modes = data["modes"]
        self.source = data.get("source", "corpus")

    def log_prob(self, mode: str, prev2: str | None, prev1: str | None, token: str) -> float:
        """Smoothed log P(token | prev2, prev1) over chord families, backing
        off to the bigram and then the unigram when there's little evidence."""
        token = reduce_token(token)
        prev1 = reduce_token(prev1) if prev1 else None
        prev2 = reduce_token(prev2) if prev2 else None
        table = self._modes[mode]
        uni = table["unigram"]
        total = table["_total"]
        vocab = max(len(uni), 1)
        p1 = (uni.get(token, 0) + 0.5) / (total + 0.5 * vocab)
        if prev1 is None:
            return math.log(max(p1, _FLOOR))
        c1 = uni.get(prev1, 0)
        c12 = table["bigram"].get(f"{prev1}|{token}", 0)
        p2 = (c12 + 2.0 * p1) / (c1 + 2.0)
        p = p2
        if prev2 is not None:
            ctx = table["bigram"].get(f"{prev2}|{prev1}", 0)
            if ctx >= 5:
                c3 = table["trigram"].get(f"{prev2}|{prev1}|{token}", 0)
                p = 0.6 * (c3 / ctx) + 0.4 * p2
        return math.log(max(p, _FLOOR))

    def share(self, mode: str, token: str) -> float:
        """How common the chord family is overall in this mode (0..1)."""
        table = self._modes[mode]
        return table["unigram"].get(reduce_token(token), 0) / max(table["_total"], 1)


def _reduce(counts: dict) -> dict:
    out: dict[str, float] = {}
    for key, value in counts.items():
        reduced = "|".join(reduce_token(t) for t in key.split("|"))
        out[reduced] = out.get(reduced, 0) + value
    return out


def _prepare(data: dict) -> dict:
    for mode, table in data["modes"].items():
        reduced = {
            "unigram": _reduce(table["unigram"]),
            "bigram": _reduce(table["bigram"]),
            "trigram": _reduce(table.get("trigram", {})),
        }
        reduced["_total"] = sum(reduced["unigram"].values())
        data["modes"][mode] = reduced
    return data


def _rule_based() -> dict:
    """A stand-in prior from functional harmony, used until the corpus
    table is built: tonic moves anywhere, predominant leads to dominant,
    dominant resolves home."""
    functions = {
        "major": {"0:maj": "T", "9:min": "T", "4:min": "T", "5:maj": "PD", "2:min": "PD",
                  "7:maj": "D", "7:7": "D", "11:dim": "D", "2:m7": "PD", "5:maj7": "PD",
                  "0:maj7": "T", "9:m7": "T"},
        "minor": {"0:min": "T", "8:maj": "T", "3:maj": "T", "5:min": "PD", "2:dim": "PD",
                  "7:maj": "D", "7:7": "D", "10:maj": "D", "7:min": "D", "11:dim": "D"},
    }
    flow = {
        "T": {"T": 0.2, "PD": 0.45, "D": 0.35},
        "PD": {"T": 0.15, "PD": 0.25, "D": 0.6},
        "D": {"T": 0.7, "PD": 0.15, "D": 0.15},
    }
    weight = {"0:maj": 3, "0:min": 3, "7:maj": 2.5, "7:7": 2, "5:maj": 2.5, "5:min": 2,
              "9:min": 2, "8:maj": 2, "3:maj": 1.5, "10:maj": 1.5}
    modes = {}
    for mode, fns in functions.items():
        unigram = {t: weight.get(t, 1.0) * 100 for t in fns}
        bigram = {}
        for a, fa in fns.items():
            same = {f: [t for t, g in fns.items() if g == f] for f in flow}
            for f, p in flow[fa].items():
                for b in same[f]:
                    bigram[f"{a}|{b}"] = unigram[a] * p * weight.get(b, 1.0) / sum(
                        weight.get(t, 1.0) for t in same[f]
                    )
        modes[mode] = {"unigram": unigram, "bigram": bigram, "trigram": {}}
    return {"source": "rules", "modes": modes}


class BlendedPrior:
    """Corpus habits mixed with textbook function. The corpus is mostly pop
    and rock, so on its own it pulls every tune toward I–IV–I loops; the
    functional half keeps folk and classical-style tunes sounding like
    themselves. `corpus_share` is the dial a style preset can turn later."""

    def __init__(self, corpus: ProgressionPrior, rules: ProgressionPrior, corpus_share: float = 0.5):
        self._corpus = corpus
        self._rules = rules
        self._share = corpus_share
        self.source = "corpus+rules"

    def log_prob(self, mode, prev2, prev1, token) -> float:
        a = math.exp(self._corpus.log_prob(mode, prev2, prev1, token))
        b = math.exp(self._rules.log_prob(mode, prev2, prev1, token))
        return math.log(max(self._share * a + (1 - self._share) * b, _FLOOR))

    def share(self, mode, token) -> float:
        return self._corpus.share(mode, token)


@lru_cache(maxsize=1)
def load_prior() -> ProgressionPrior | BlendedPrior:
    rules = ProgressionPrior(_prepare(_rule_based()))
    if _DATA.exists():
        corpus = ProgressionPrior(_prepare(json.loads(_DATA.read_text())))
        return BlendedPrior(corpus, rules)
    return rules
