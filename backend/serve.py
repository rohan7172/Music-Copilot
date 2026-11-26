"""Starts the backend for the desktop app (or by hand), setting it up first.

    python3.11 serve.py [--port 8000]

- Creates backend/venv with the Python running this script if it's missing.
- (Re)installs requirements.txt when it changed since the last install.
- Runs uvicorn on 127.0.0.1:<port> from inside the venv.
- With --exit-with-stdin, stops the server once stdin closes. The desktop
  app keeps a pipe open to this process for as long as it runs, so the
  backend goes away with the app even if the app crashes or is force-quit.

Progress lines start with "serve:" so the app can show what's happening.
"""

import argparse
import filecmp
import os
import shutil
import signal
import subprocess
import sys
import threading
from pathlib import Path

BACKEND = Path(__file__).resolve().parent
VENV = BACKEND / "venv"
REQUIREMENTS = BACKEND / "requirements.txt"
INSTALLED = VENV / ".requirements.installed"


def say(message: str) -> None:
    print(f"serve: {message}", flush=True)


def venv_python() -> Path:
    if os.name == "nt":
        return VENV / "Scripts" / "python.exe"
    return VENV / "bin" / "python"


def ensure_venv() -> None:
    if venv_python().exists():
        return
    if sys.version_info[:2] != (3, 11):
        say(
            f"warning: creating the venv with Python "
            f"{sys.version_info.major}.{sys.version_info.minor}; "
            "Basic Pitch needs 3.11"
        )
    say("creating the Python environment (first run)")
    subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)


def ensure_requirements() -> None:
    if INSTALLED.exists() and filecmp.cmp(REQUIREMENTS, INSTALLED, shallow=False):
        return
    say("installing packages (first run or requirements changed; this takes a while)")
    subprocess.run(
        [str(venv_python()), "-m", "pip", "install", "-q", "-r", str(REQUIREMENTS)],
        check=True,
    )
    shutil.copyfile(REQUIREMENTS, INSTALLED)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--exit-with-stdin", action="store_true")
    args = parser.parse_args()

    ensure_venv()
    ensure_requirements()

    say(f"starting the server on port {args.port}")
    server = subprocess.Popen(
        [
            str(venv_python()),
            "-m",
            "uvicorn",
            "app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(args.port),
        ],
        cwd=BACKEND,
    )

    # Pass a polite shutdown on to the server instead of orphaning it.
    signal.signal(signal.SIGTERM, lambda *_: server.terminate())

    if args.exit_with_stdin:

        def watch_stdin() -> None:
            try:
                while sys.stdin.read(1):
                    pass
            except (OSError, ValueError):
                pass
            server.terminate()

        threading.Thread(target=watch_stdin, daemon=True).start()

    try:
        return server.wait()
    except KeyboardInterrupt:
        server.terminate()
        return server.wait()


if __name__ == "__main__":
    sys.exit(main())
