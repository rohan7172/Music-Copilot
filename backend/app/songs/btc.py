"""BTC: a bi-directional transformer that recognises chords from audio.

Vendored (inference only) from https://github.com/jayg996/BTC-ISMIR19 at
commit 2682317, MIT licence (see BTC_LICENSE in this folder). Park et al.,
"A Bi-Directional Transformer for Musical Chord Recognition", ISMIR 2019.

Changes from the original, after reviewing it line by line: training
code, loss functions and the yaml config loader (which used the unsafe
`yaml.load`) are removed; the config lives in `_CONFIG` below; `np.float`
(removed in numpy 2) is `np.float64`. Layer and attribute names are kept
exactly, because the checkpoint's weights are matched to them by name.

Loading is the safe kind: `torch.load(..., weights_only=True)` only
rebuilds tensors and plain data, never runs code from the file, and the
file's SHA-256 is checked against the one published at that commit. See
"Loading model weights safely" in docs/concepts.md.
"""

import hashlib
import math
from pathlib import Path

import librosa
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

WEIGHTS_DIR = Path(__file__).resolve().parents[2] / "models"
WEIGHTS_FILE = "btc_model_large_voca.pt"
WEIGHTS_SHA256 = "1673d23f8f9a55ae7f9e8b80a51da616debb22675b8d8b67ea6ce0ef37b0ab51"

SAMPLE_RATE = 22050
_HOP = 2048
_TIMESTEP = 108  # frames per inference window (10 s of audio)

_CONFIG = {
    "feature_size": 144, "timestep": _TIMESTEP, "num_chords": 170,
    "num_layers": 8, "num_heads": 4, "hidden_size": 128,
    "total_key_depth": 128, "total_value_depth": 128, "filter_size": 128,
}

# The large vocabulary: 12 roots x 14 qualities, then "X" (unknown) and
# "N" (no chord). Collapsed onto the harmoniser's qualities.
_BTC_QUALITIES = ["min", "maj", "dim", "aug", "min6", "maj6", "min7", "minmaj7",
                  "maj7", "7", "dim7", "hdim7", "sus2", "sus4"]
_TO_OURS = {"min": "min", "maj": "maj", "dim": "dim", "aug": "aug", "min6": "min",
            "maj6": "maj", "min7": "m7", "minmaj7": "min", "maj7": "maj7", "7": "7",
            "dim7": "dim", "hdim7": "m7b5", "sus2": "sus2", "sus4": "sus4"}
NUM_CLASSES = 170
NO_CHORD = 169
UNKNOWN = 168


def class_chord(index: int) -> tuple[int, str] | None:
    """(root pitch class, harmoniser quality) for a BTC class, or None for
    N / X."""
    if index >= 168:
        return None
    return index // 14, _TO_OURS[_BTC_QUALITIES[index % 14]]


# --- The network (unchanged structure) --------------------------------------


def _gen_bias_mask(max_length):
    np_mask = np.triu(np.full([max_length, max_length], -np.inf), 1)
    return torch.from_numpy(np_mask).type(torch.FloatTensor).unsqueeze(0).unsqueeze(1)


def _gen_timing_signal(length, channels, min_timescale=1.0, max_timescale=1.0e4):
    position = np.arange(length)
    num_timescales = channels // 2
    log_increment = math.log(float(max_timescale) / float(min_timescale)) / (float(num_timescales) - 1)
    inv_timescales = min_timescale * np.exp(np.arange(num_timescales).astype(np.float64) * -log_increment)
    scaled_time = np.expand_dims(position, 1) * np.expand_dims(inv_timescales, 0)
    signal = np.concatenate([np.sin(scaled_time), np.cos(scaled_time)], axis=1)
    signal = np.pad(signal, [[0, 0], [0, channels % 2]], "constant", constant_values=[0.0, 0.0])
    return torch.from_numpy(signal.reshape([1, length, channels])).type(torch.FloatTensor)


class LayerNorm(nn.Module):
    def __init__(self, features, eps=1e-6):
        super().__init__()
        self.gamma = nn.Parameter(torch.ones(features))
        self.beta = nn.Parameter(torch.zeros(features))
        self.eps = eps

    def forward(self, x):
        mean = x.mean(-1, keepdim=True)
        std = x.std(-1, keepdim=True)
        return self.gamma * (x - mean) / (std + self.eps) + self.beta


class OutputLayer(nn.Module):
    def __init__(self, hidden_size, output_size):
        super().__init__()
        self.output_size = output_size
        self.output_projection = nn.Linear(hidden_size, output_size)
        # Unused at inference, but its weights are in the checkpoint, and
        # a strict load needs every layer present.
        self.lstm = nn.LSTM(input_size=hidden_size, hidden_size=int(hidden_size / 2), batch_first=True, bidirectional=True)

    def forward(self, hidden):
        return F.softmax(self.output_projection(hidden), -1)


class MultiHeadAttention(nn.Module):
    def __init__(self, input_depth, total_key_depth, total_value_depth, output_depth, num_heads, bias_mask=None):
        super().__init__()
        self.num_heads = num_heads
        self.query_scale = (total_key_depth // num_heads) ** -0.5
        self.bias_mask = bias_mask
        self.query_linear = nn.Linear(input_depth, total_key_depth, bias=False)
        self.key_linear = nn.Linear(input_depth, total_key_depth, bias=False)
        self.value_linear = nn.Linear(input_depth, total_value_depth, bias=False)
        self.output_linear = nn.Linear(total_value_depth, output_depth, bias=False)

    def _split_heads(self, x):
        s = x.shape
        return x.view(s[0], s[1], self.num_heads, s[2] // self.num_heads).permute(0, 2, 1, 3)

    def _merge_heads(self, x):
        s = x.shape
        return x.permute(0, 2, 1, 3).contiguous().view(s[0], s[2], s[3] * self.num_heads)

    def forward(self, queries, keys, values):
        queries = self._split_heads(self.query_linear(queries)) * self.query_scale
        keys = self._split_heads(self.key_linear(keys))
        values = self._split_heads(self.value_linear(values))
        logits = torch.matmul(queries, keys.permute(0, 1, 3, 2))
        if self.bias_mask is not None:
            logits += self.bias_mask[:, :, : logits.shape[-2], : logits.shape[-1]].type_as(logits.data)
        weights = F.softmax(logits, dim=-1)
        return self.output_linear(self._merge_heads(torch.matmul(weights, values)))


class Conv(nn.Module):
    def __init__(self, input_size, output_size, kernel_size):
        super().__init__()
        self.pad = nn.ConstantPad1d((kernel_size // 2, (kernel_size - 1) // 2), 0)
        self.conv = nn.Conv1d(input_size, output_size, kernel_size=kernel_size, padding=0)

    def forward(self, inputs):
        return self.conv(self.pad(inputs.permute(0, 2, 1))).permute(0, 2, 1)


class PositionwiseFeedForward(nn.Module):
    def __init__(self, input_depth, filter_size, output_depth):
        super().__init__()
        self.layers = nn.ModuleList([Conv(input_depth, filter_size, 3), Conv(filter_size, output_depth, 3)])
        self.relu = nn.ReLU()

    def forward(self, x):
        for layer in self.layers:
            x = self.relu(layer(x))
        return x


class SelfAttentionBlock(nn.Module):
    def __init__(self, hidden, key_depth, value_depth, filter_size, heads, bias_mask):
        super().__init__()
        self.multi_head_attention = MultiHeadAttention(hidden, key_depth, value_depth, hidden, heads, bias_mask)
        self.positionwise_convolution = PositionwiseFeedForward(hidden, filter_size, hidden)
        self.layer_norm_mha = LayerNorm(hidden)
        self.layer_norm_ffn = LayerNorm(hidden)

    def forward(self, x):
        x_norm = self.layer_norm_mha(x)
        x = x + self.multi_head_attention(x_norm, x_norm, x_norm)
        return x + self.positionwise_convolution(self.layer_norm_ffn(x))


class BiDirectionalSelfAttention(nn.Module):
    def __init__(self, hidden, key_depth, value_depth, filter_size, heads, max_length):
        super().__init__()
        mask = _gen_bias_mask(max_length)
        self.attn_block = SelfAttentionBlock(hidden, key_depth, value_depth, filter_size, heads, mask)
        self.backward_attn_block = SelfAttentionBlock(
            hidden, key_depth, value_depth, filter_size, heads, torch.transpose(mask, dim0=2, dim1=3)
        )
        self.linear = nn.Linear(hidden * 2, hidden)

    def forward(self, x):
        return self.linear(torch.cat((self.attn_block(x), self.backward_attn_block(x)), dim=2))


class BiDirectionalSelfAttentionLayers(nn.Module):
    def __init__(self, c):
        super().__init__()
        h = c["hidden_size"]
        self.timing_signal = _gen_timing_signal(c["timestep"], h)
        self.embedding_proj = nn.Linear(c["feature_size"], h, bias=False)
        self.self_attn_layers = nn.Sequential(
            *[
                BiDirectionalSelfAttention(h, c["total_key_depth"], c["total_value_depth"], c["filter_size"], c["num_heads"], c["timestep"])
                for _ in range(c["num_layers"])
            ]
        )
        self.layer_norm = LayerNorm(h)

    def forward(self, inputs):
        x = self.embedding_proj(inputs)
        x = x + self.timing_signal[:, : inputs.shape[1], :].type_as(inputs.data)
        return self.layer_norm(self.self_attn_layers(x))


class BTCModel(nn.Module):
    def __init__(self, c=_CONFIG):
        super().__init__()
        self.self_attn_layers = BiDirectionalSelfAttentionLayers(c)
        self.output_layer = OutputLayer(c["hidden_size"], c["num_chords"])

    def forward(self, features):
        """Chord-class probabilities per frame, (batch, frames, 170)."""
        return self.output_layer(self.self_attn_layers(features))


# --- Safe loading and inference ---------------------------------------------


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load(weights_dir: Path = WEIGHTS_DIR) -> tuple[BTCModel, np.ndarray, np.ndarray]:
    """The model plus the feature mean and std it was trained with.

    Refuses a weights file whose hash doesn't match the published one, then
    loads it with `weights_only=True`, allowing exactly the numpy pieces
    needed to rebuild the two normalisation arrays and nothing else."""
    path = weights_dir / WEIGHTS_FILE
    if not path.exists():
        raise FileNotFoundError(
            f"{path} is missing. Run `backend/venv/bin/python scripts/fetch_btc_weights.py`."
        )
    if _sha256(path) != WEIGHTS_SHA256:
        raise ValueError(f"{path} doesn't match the published BTC weights; refusing to load it.")
    # Rebuilding an array or a single number from its dtype and raw bytes:
    # data only, nothing that can call arbitrary code. The checkpoint was
    # saved with numpy 1, so each is registered under its old module path.
    from numpy._core import multiarray

    safe_numpy = [
        (multiarray._reconstruct, "numpy.core.multiarray._reconstruct"),
        (multiarray.scalar, "numpy.core.multiarray.scalar"),
        np.ndarray,
        np.dtype,
        type(np.dtype(np.float64)),
        type(np.dtype(np.float32)),
    ]
    with torch.serialization.safe_globals(safe_numpy):
        checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    model = BTCModel()
    model.load_state_dict(checkpoint["model"])
    model.eval()
    return model, np.asarray(checkpoint["mean"]), np.asarray(checkpoint["std"])


def features(audio: np.ndarray) -> np.ndarray:
    """Log-magnitude constant-Q transform, (frames, 144): 6 octaves at 24
    bins per octave, one frame per 2048 samples (~10.8 frames a second)."""
    cqt = librosa.cqt(audio, sr=SAMPLE_RATE, n_bins=144, bins_per_octave=24, hop_length=_HOP)
    return np.log(np.abs(cqt) + 1e-6).T


FRAME_SECONDS = _HOP / SAMPLE_RATE


def chord_probabilities(model: BTCModel, mean, std, audio: np.ndarray) -> np.ndarray:
    """Per-frame probabilities over the 170 chord classes for mono audio at
    SAMPLE_RATE, (frames, 170), one frame every FRAME_SECONDS."""
    feat = (features(audio) - mean) / std
    frames = len(feat)
    pad = (-frames) % _TIMESTEP
    x = torch.tensor(np.pad(feat, ((0, pad), (0, 0))), dtype=torch.float32)[None]
    out = []
    with torch.no_grad():
        for i in range(x.shape[1] // _TIMESTEP):
            out.append(model(x[:, i * _TIMESTEP : (i + 1) * _TIMESTEP])[0])
    return torch.cat(out)[:frames].numpy()
