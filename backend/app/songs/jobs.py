"""Background jobs for the slow song analysis: start one, poll its stage.

A thread per job and an in-memory table, which is all a single local
backend process needs (no queue server). Jobs are forgotten after an hour.
"""

import threading
import time
import traceback
import uuid
from collections.abc import Callable

_jobs: dict[str, dict] = {}
_lock = threading.Lock()
_KEEP_SECONDS = 3600


def start(work: Callable[[Callable[[str, float], None]], dict]) -> str:
    """Runs `work(progress)` in the background and returns the job id.
    `work` reports progress by calling progress(stage, fraction)."""
    job_id = uuid.uuid4().hex[:12]
    with _lock:
        _forget_old()
        _jobs[job_id] = {"status": "running", "stage": "Starting", "progress": 0.0, "started": time.time()}

    def progress(stage: str, fraction: float) -> None:
        with _lock:
            _jobs[job_id].update(stage=stage, progress=round(fraction, 2))

    def run() -> None:
        try:
            result = work(progress)
            with _lock:
                _jobs[job_id].update(status="done", progress=1.0, stage="Done", result=result)
        except Exception as e:
            traceback.print_exc()
            with _lock:
                _jobs[job_id].update(status="failed", error=str(e))

    threading.Thread(target=run, daemon=True).start()
    return job_id


def get(job_id: str) -> dict | None:
    with _lock:
        job = _jobs.get(job_id)
        return None if job is None else {k: v for k, v in job.items() if k != "started"}


def _forget_old() -> None:
    now = time.time()
    for job_id in [j for j, v in _jobs.items() if now - v["started"] > _KEEP_SECONDS]:
        del _jobs[job_id]
