"""ETag / If-None-Match on the read routes the app polls (issue #27)."""

import pytest


def _make_card(client, mock_xai, word="juice", folder_id=None):
    body = {"word": word}
    if folder_id:
        body["folder_id"] = folder_id
    resp = client.post("/v1/cards", json=body)
    assert resp.status_code == 200
    return resp.json()


@pytest.mark.parametrize("path", ["/v1/board", "/v1/cards"])
def test_read_routes_send_an_etag_and_revalidate_header(client, path):
    resp = client.get(path)
    assert resp.status_code == 200
    etag = resp.headers["etag"]
    assert etag.startswith('"') and etag.endswith('"')
    assert resp.headers["cache-control"] == "no-cache"


@pytest.mark.parametrize("path", ["/v1/board", "/v1/cards"])
def test_same_content_gives_the_same_etag(client, path):
    first = client.get(path).headers["etag"]
    second = client.get(path).headers["etag"]
    assert first == second


@pytest.mark.parametrize("path", ["/v1/board", "/v1/cards"])
def test_if_none_match_returns_304_with_no_body(client, path):
    etag = client.get(path).headers["etag"]
    resp = client.get(path, headers={"If-None-Match": etag})
    assert resp.status_code == 304
    assert resp.content == b""
    assert resp.headers["etag"] == etag


def test_weak_and_listed_validators_match(client):
    etag = client.get("/v1/board").headers["etag"]
    assert client.get("/v1/board", headers={"If-None-Match": f"W/{etag}"}).status_code == 304
    assert client.get("/v1/board", headers={"If-None-Match": f'"other", {etag}'}).status_code == 304
    assert client.get("/v1/board", headers={"If-None-Match": "*"}).status_code == 304


def test_stale_validator_returns_the_full_board(client):
    resp = client.get("/v1/board", headers={"If-None-Match": '"not-the-current-version"'})
    assert resp.status_code == 200
    assert resp.json()["folder_id"] is None


def test_etag_changes_when_the_board_changes(client, mock_xai):
    before = client.get("/v1/board").headers["etag"]
    assert client.post("/v1/folders", json={"name": "Food"}).status_code == 200
    resp = client.get("/v1/board", headers={"If-None-Match": before})
    assert resp.status_code == 200
    assert resp.headers["etag"] != before
    assert any(item["slug"] == "food" for item in resp.json()["items"])

    _make_card(client, mock_xai, word="juice", folder_id="food")
    folder_before = client.get("/v1/board", params={"folder_id": "food"})
    assert folder_before.status_code == 200
    assert client.get(
        "/v1/board", params={"folder_id": "food"}, headers={"If-None-Match": folder_before.headers["etag"]}
    ).status_code == 304
    _make_card(client, mock_xai, word="apple", folder_id="food")
    folder_after = client.get(
        "/v1/board", params={"folder_id": "food"}, headers={"If-None-Match": folder_before.headers["etag"]}
    )
    assert folder_after.status_code == 200
    assert folder_after.headers["etag"] != folder_before.headers["etag"]


def test_missing_folder_is_still_404(client):
    resp = client.get("/v1/board", params={"folder_id": "nope"}, headers={"If-None-Match": "*"})
    assert resp.status_code == 404


def test_assets_are_conditional_too(client, mock_xai):
    card = _make_card(client, mock_xai, word="juice")
    for url in (card["image_url"], card["audio_url"]):
        first = client.get(url)
        assert first.status_code == 200
        etag = first.headers["etag"]
        assert client.get(url, headers={"If-None-Match": etag}).status_code == 304
        assert client.get(url, headers={"If-Modified-Since": first.headers["last-modified"]}).status_code == 304
