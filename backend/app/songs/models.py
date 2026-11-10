"""The song path's three pretrained models, loaded lazily (the first song
upload pays the load; melody takes never do) and kept for the process.

- Demucs (htdemucs): splits a mix into drums, bass, other and vocals.
- Beat This!: beats and downbeats.
- BTC: chord probabilities per frame (see btc.py).
"""

import threading
from functools import lru_cache

import numpy as np
import torch

_lock = threading.Lock()


def device() -> str:
    return "mps" if torch.backends.mps.is_available() else "cpu"


def available() -> bool:
    """Whether the song stack is installed (requirements-songs.txt) and
    BTC's weights are present (scripts/fetch_btc_weights.py)."""
    try:
        import beat_this  # noqa: F401
        import demucs  # noqa: F401
    except ImportError:
        return False
    from app.songs.btc import WEIGHTS_DIR, WEIGHTS_FILE

    return (WEIGHTS_DIR / WEIGHTS_FILE).exists()


@lru_cache(maxsize=1)
def _demucs():
    from demucs.pretrained import get_model

    model = get_model("htdemucs")
    model.to(device())
    model.eval()
    return model


@lru_cache(maxsize=1)
def _beats():
    from beat_this.inference import Audio2Beats

    return Audio2Beats(checkpoint_path="final0", device=device(), dbn=False)


@lru_cache(maxsize=1)
def _btc():
    from app.songs import btc

    return btc.load()


def separate(stereo: np.ndarray, sample_rate: int) -> dict[str, np.ndarray]:
    """Stems as mono float arrays at the model's rate (44.1 kHz): drums,
    bass, other, vocals. `stereo` is (2, samples) at that rate."""
    from demucs.apply import apply_model

    with _lock:
        model = _demucs()
        wav = torch.tensor(stereo, dtype=torch.float32)
        ref = wav.mean(0)
        mean, std = ref.mean(), ref.std() + 1e-8
        with torch.no_grad():
            out = apply_model(model, ((wav - mean) / std)[None].to(device()), device=device(), progress=False)[0]
        out = (out.cpu() * std + mean).numpy()
    return {name: out[i].mean(axis=0) for i, name in enumerate(model.sources)}


def beats(mono: np.ndarray, sample_rate: int) -> tuple[np.ndarray, np.ndarray]:
    """(beat times, downbeat times) in seconds."""
    with _lock:
        b, d = _beats()(mono, sample_rate)
    return np.asarray(b), np.asarray(d)


def chord_probabilities(mono_22k: np.ndarray) -> np.ndarray:
    from app.songs import btc

    with _lock:
        model, mean, std = _btc()
        return btc.chord_probabilities(model, mean, std, mono_22k)
