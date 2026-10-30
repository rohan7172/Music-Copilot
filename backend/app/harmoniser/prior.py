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


class ProgressionPrior:
    def __init__(self, data: dict):
        self._modes = data["modes"]
        self.source = data.get("source", "corpus")

    def log_prob(self, mode: str, prev2: str | None, prev1: str | None, token: str) -> float:
        """Smoothed log P(token | prev2, prev1), backing off to the bigram
        and then the unigram when there's too little evidence."""
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
        """How common the chord is overall in this mode (0..1)."""
        table = self._modes[mode]
        return table["unigram"].get(token, 0) / max(table["_total"], 1)


def _prepare(data: dict) -> dict:
    for table in data["modes"].values():
        table["_total"] = sum(table["unigram"].values())
        table.setdefault("trigram", {})
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


@lru_cache(maxsize=1)
def load_prior() -> ProgressionPrior:
    if _DATA.exists():
        return ProgressionPrior(_prepare(json.loads(_DATA.read_text())))
    return ProgressionPrior(_prepare(_rule_based()))
