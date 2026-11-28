"""Where data lives. Kept separate so sync and main agree without a circular import."""

from __future__ import annotations

import os
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent


def data_root() -> Path:
    override = os.environ.get("BESTWISHES_DATA_DIR", "").strip()
    return Path(override).expanduser().resolve() if override else BACKEND_ROOT / "data"
