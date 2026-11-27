"""Board and cards API shapes against docs/CONTRACT.md. xAI is mocked."""

import pytest

def test_empty_root_board_shape(client):
    resp = client.get("/v1/board")
    assert resp.status_code == 200
    body = resp.json()
    assert body["folder_id"] is None
    assert body["count"] == len(body["items"])
    assert isinstance(body["items"], list)


def test_create_folder_shape(client):
    resp = client.post("/v1/folders", json={"name": "Food"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["kind"] == "folder"
    assert body["name"] == "Food"
    assert body["word"] == "Food"
    assert body["slug"] == "food"
    assert body["image_url"] == "/system/folder.png"
    assert body["folder_id"] is None
    assert body["children"] == []
    assert "created_at" in body

    root = client.get("/v1/board").json()
    slugs = [item["slug"] for item in root["items"]]
    assert "food" in slugs
    food = next(item for item in root["items"] if item["slug"] == "food")
    assert food["kind"] == "folder"


def test_create_card_mocked_xai_and_folder_membership(client, mock_xai):
    assert client.post("/v1/folders", json={"name": "Food"}).status_code == 200

    resp = client.post("/v1/cards", json={"word": "ice cream", "folder_id": "food"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["kind"] == "word"
    assert body["word"] == "ice cream"
    assert body["slug"] == "ice-cream"
    assert body["folder_id"] == "food"
    assert body["image_url"] == "/assets/ice-cream/image.png"
    assert body["audio_url"] == "/assets/ice-cream/audio.mp3"
    assert body["image_bytes"] > 0
    assert body["audio_bytes"] > 0
    assert "created_at" in body

    # Card is not on the root board; it lives in the folder.
    root = client.get("/v1/board").json()
    root_slugs = [item["slug"] for item in root["items"]]
    assert "ice-cream" not in root_slugs
    assert "food" in root_slugs

    inside = client.get("/v1/board", params={"folder_id": "food"})
    assert inside.status_code == 200
    folder_body = inside.json()
    assert folder_body["folder_id"] == "food"
    assert folder_body["count"] == 1
    child = folder_body["items"][0]
    assert child["kind"] == "word"
    assert child["slug"] == "ice-cream"
    assert child["word"] == "ice cream"
    assert child["folder_id"] == "food"
    assert child["image_url"] == "/assets/ice-cream/image.png"
    assert child["audio_url"] == "/assets/ice-cream/audio.mp3"

    flat = client.get("/v1/cards")
    assert flat.status_code == 200
    listed = flat.json()
    assert listed["count"] == 1
    assert listed["cards"][0]["slug"] == "ice-cream"
    assert listed["cards"][0]["kind"] == "word"
    assert listed["cards"][0]["folder_id"] == "food"

    one = client.get("/v1/cards/ice-cream")
    assert one.status_code == 200
    assert one.json()["kind"] == "word"
    assert one.json()["folder_id"] == "food"

    asset = client.get("/assets/ice-cream/image.png")
    assert asset.status_code == 200
    assert asset.content.startswith(b"\x89PNG")


def test_existing_card_is_not_regenerated(client, mock_xai, monkeypatch):
    first = client.post("/v1/cards", json={"word": "juice"})
    assert first.status_code == 200

    def fail(*_args, **_kwargs):
        raise AssertionError("xAI generate should not run for an existing card")

    monkeypatch.setattr("app.main.generate_image", fail)
    monkeypatch.setattr("app.main.generate_tts", fail)

    again = client.post("/v1/cards", json={"word": "juice"})
    assert again.status_code == 200
    assert again.json()["slug"] == "juice"
    assert again.json()["kind"] == "word"
    assert again.json()["folder_id"] is None


def test_delete_folder_moves_children_to_root(client, mock_xai):
    assert client.post("/v1/folders", json={"name": "Food"}).status_code == 200
    assert client.post("/v1/cards", json={"word": "juice", "folder_id": "food"}).status_code == 200

    deleted = client.delete("/v1/folders/food")
    assert deleted.status_code == 200
    body = deleted.json()
    assert body == {"ok": True, "deleted": "food", "moved_to_root": ["juice"]}

    root = client.get("/v1/board").json()
    slugs = [item["slug"] for item in root["items"]]
    assert "food" not in slugs
    assert "juice" in slugs
    juice = next(item for item in root["items"] if item["slug"] == "juice")
    assert juice["kind"] == "word"
    assert juice["folder_id"] is None


def test_delete_card(client, mock_xai):
    assert client.post("/v1/cards", json={"word": "bubble"}).status_code == 200
    resp = client.delete("/v1/cards/bubble")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True, "deleted": "bubble"}
    assert client.get("/v1/cards/bubble").status_code == 404


def test_unknown_folder_is_404(client):
    resp = client.get("/v1/board", params={"folder_id": "missing"})
    assert resp.status_code == 404


def test_create_card_without_mock_fails_without_api_key(client):
    """A missing XAI_API_KEY must not be papered over; no live xAI calls."""
    with pytest.raises(RuntimeError, match="XAI_API_KEY not found"):
        client.post("/v1/cards", json={"word": "bananas"})
