"""POST /v1/cards/{slug}/image makes a new picture for an existing card."""

from __future__ import annotations

from pathlib import Path

from app import main as app_main


def _fake_image_writer(tag: str):
    async def fake_image(client, word: str, dest: Path):
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"\x89PNG\r\n\x1a\n" + f"{tag}:{word}".encode())
        return {"bytes": dest.stat().st_size, "prompt": f"{tag} {word}", "model": "mock-image"}

    return fake_image


def test_regenerate_replaces_picture_keeps_audio_and_previous(client, mock_xai, monkeypatch, data_root):
    assert client.post("/v1/cards", json={"word": "juice"}).status_code == 200
    before = client.get("/assets/juice/image.png")
    audio_before = client.get("/assets/juice/audio.mp3").content

    monkeypatch.setattr(app_main, "generate_image", _fake_image_writer("second"))
    res = client.post("/v1/cards/juice/image")
    assert res.status_code == 200, res.text
    assert res.json()["slug"] == "juice"
    assert res.json()["image_url"].endswith("/assets/juice/image.png")

    after = client.get("/assets/juice/image.png")
    assert after.content.endswith(b"second:juice")
    assert after.content != before.content
    assert after.headers.get("etag") != before.headers.get("etag")
    assert client.get("/assets/juice/audio.mp3").content == audio_before
    assert (app_main.DATA_DIR / "juice" / "image.prev.png").read_bytes() == before.content


def test_regenerate_unknown_card_is_404(client, mock_xai):
    assert client.post("/v1/cards/nope/image").status_code == 404


def test_regenerate_cooldown_and_daily_cap(client, mock_xai, monkeypatch):
    assert client.post("/v1/cards", json={"word": "juice"}).status_code == 200
    assert client.post("/v1/cards", json={"word": "milk"}).status_code == 200
    assert client.post("/v1/cards/juice/image").status_code == 200
    assert client.post("/v1/cards/juice/image").status_code == 429, "same card again inside the cooldown"

    monkeypatch.setattr(app_main, "REGEN_DAILY_CAP", 1)
    assert client.post("/v1/cards/milk/image").status_code == 429, "daily cap reached"


def _hint_recorder(calls: list):
    async def fake_image(client, word: str, dest: Path, hint=None):
        calls.append((word, hint))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"\x89PNG\r\n\x1a\n" + f"{word}:{hint}".encode())
        return {"bytes": dest.stat().st_size, "prompt": app_main.pecs_prompt(word, hint), "model": "mock-image"}

    return fake_image


def test_meaning_hint_steers_the_prompt():
    plain = app_main.pecs_prompt("can")
    hinted = app_main.pecs_prompt("can", "  able to,\n  be allowed to  ")
    assert "means" not in plain
    assert hinted.startswith(plain)
    assert 'The word "can" here means: able to, be allowed to.' in hinted
    assert app_main.clean_hint("   ") is None
    assert len(app_main.clean_hint("x" * 500)) == app_main.HINT_MAX_CHARS


def test_create_with_hint_saves_it_and_regenerate_reuses_or_replaces_it(client, mock_xai, monkeypatch):
    calls: list = []
    monkeypatch.setattr(app_main, "generate_image", _hint_recorder(calls))
    monkeypatch.setattr(app_main, "REGEN_COOLDOWN_SECONDS", 0)
    assert client.post("/v1/cards", json={"word": "can", "hint": "able to"}).status_code == 200
    assert calls[-1] == ("can", "able to")
    assert app_main.read_meta("can")["hint"] == "able to"

    assert client.post("/v1/cards/can/image").status_code == 200
    assert calls[-1] == ("can", "able to"), "no body reuses the saved hint"

    assert client.post("/v1/cards/can/image", json={"hint": "be able to do something"}).status_code == 200
    assert calls[-1] == ("can", "be able to do something")
    assert app_main.read_meta("can")["hint"] == "be able to do something"


def test_create_without_hint_is_unchanged(client, mock_xai):
    assert client.post("/v1/cards", json={"word": "juice"}).status_code == 200
    assert "hint" not in app_main.read_meta("juice")
