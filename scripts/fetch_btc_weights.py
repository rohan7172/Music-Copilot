"""Downloads the BTC chord-recognition weights into backend/models/.

Fetched from the BTC repository at a pinned commit and checked against
the file's published SHA-256 before it's kept, so the app only ever loads
the exact weights that were reviewed (see app/songs/btc.py). The weights
aren't committed to this repo.

Usage (from the repo root):
    backend/venv/bin/python scripts/fetch_btc_weights.py
"""

import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))

from app.songs.btc import WEIGHTS_DIR, WEIGHTS_FILE, WEIGHTS_SHA256  # noqa: E402

COMMIT = "2682317be668032e6e4b269ded36adaa2ad57df0"
URL = f"https://raw.githubusercontent.com/jayg996/BTC-ISMIR19/{COMMIT}/test/{WEIGHTS_FILE}"


def main() -> None:
    target = WEIGHTS_DIR / WEIGHTS_FILE
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == WEIGHTS_SHA256:
        print(f"{target} already present and verified.")
        return
    print(f"Downloading {URL}")
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != WEIGHTS_SHA256:
        sys.exit(f"Checksum mismatch ({digest}); not saving the file.")
    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    print(f"Saved and verified {target} ({len(data) / 1e6:.1f} MB).")


if __name__ == "__main__":
    main()
