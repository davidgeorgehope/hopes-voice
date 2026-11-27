"""Isolate generated assets and refuse a real xAI key during tests."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

import httpx
import pytest

# Must run before `app.main` is imported: paths and StaticFiles mounts are
# fixed at import time.
os.environ["XAI_API_KEY"] = ""
# Hide any developer credentials.env so tests never pick up a real key.
os.environ["HOME"] = tempfile.mkdtemp(prefix="bw-testhome-")
_DATA = Path(tempfile.mkdtemp(prefix="bw-testdata-"))
os.environ["BESTWISHES_DATA_DIR"] = str(_DATA)

from fastapi.testclient import TestClient  # noqa: E402

from app import main as app_main  # noqa: E402


@pytest.fixture(scope="session")
def data_root() -> Path:
    return Path(os.environ["BESTWISHES_DATA_DIR"])


@pytest.fixture(autouse=True)
def _clean_data(data_root: Path):
    """Start each test with an empty board and no cards."""
    if data_root.exists():
        shutil.rmtree(data_root)
    (data_root / "cards").mkdir(parents=True)
    (data_root / "system").mkdir(parents=True)
    yield


@pytest.fixture(autouse=True)
def _block_live_xai(monkeypatch):
    """Fail loudly if a test would call api.x.ai, even when a key is present."""
    original_request = httpx.AsyncClient.request

    async def guarded_request(self, method, url, *args, **kwargs):
        if "api.x.ai" in str(url):
            raise AssertionError(f"tests must not call the live xAI API: {method} {url}")
        return await original_request(self, method, url, *args, **kwargs)

    monkeypatch.setattr(httpx.AsyncClient, "request", guarded_request)


@pytest.fixture
def client() -> TestClient:
    return TestClient(app_main.app)


@pytest.fixture
def mock_xai(monkeypatch):
    """Write fake image + audio assets; never call the xAI API."""

    async def fake_image(client, word: str, dest: Path):
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"\x89PNG\r\n\x1a\n" + f"fake-image:{word}".encode())
        return {
            "bytes": dest.stat().st_size,
            "prompt": f"mock pecs for {word}",
            "model": "mock-image",
        }

    async def fake_tts(client, word: str, dest: Path):
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"ID3" + f"fake-audio:{word}".encode())
        return {"bytes": dest.stat().st_size, "voice_id": "eve"}

    monkeypatch.setattr(app_main, "generate_image", fake_image)
    monkeypatch.setattr(app_main, "generate_tts", fake_tts)
    return True
