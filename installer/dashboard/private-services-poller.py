"""Bounded private-service cache writer; network adapters are owner-configured later."""
from __future__ import annotations
import json
import os
import tempfile
import time
from pathlib import Path

MAX_AGE_SECONDS = 25 * 60
MIN_START_SECONDS = 60

def cache_path(root: Path) -> Path:
    return root / "private-services-cache.json"

def is_stale(payload: dict, now: float | None = None) -> bool:
    checked = float(payload.get("checked_at", 0))
    return (time.time() if now is None else now) - checked > MAX_AGE_SECONDS

def write_cache(root: Path, payload: dict) -> Path:
    target = cache_path(root)
    data = {"checked_at": time.time(), "mail": payload.get("mail"), "calendar": payload.get("calendar"), "status": payload.get("status", "pending-owner")}
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=root, delete=False) as stream:
        json.dump(data, stream)
        temporary = Path(stream.name)
    os.replace(temporary, target)
    return target

if __name__ == "__main__":
    root = Path(os.environ.get("JARVIS_PROJECT_ROOT", Path.cwd()))
    root.mkdir(parents=True, exist_ok=True)
    write_cache(root, {"status": "pending-owner", "mail": None, "calendar": None})
