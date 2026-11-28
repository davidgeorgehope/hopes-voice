"""Remote board sync API. Synthetic profile only: no private vocabulary, names or photos."""

import copy
import hashlib
import json
from pathlib import Path

import pytest

ADMIN = "test-admin-token"
BOARD = json.loads((Path(__file__).parent / "fixtures" / "sample.board.json").read_text())


def doc(**overlays):
    base = {
        "format": "bestwishes.sync/v1",
        "board": None,
        "overlays": {"hidden": [], "order": {}, "labels": {}, "positions": {}, "speak": {}, "styles": {}},
        "images": {},
    }
    base["overlays"].update(overlays)
    return base


@pytest.fixture(autouse=True)
def _admin(monkeypatch):
    monkeypatch.setenv("HOPESVOICE_ADMIN_TOKEN", ADMIN)


def auth(token=ADMIN):
    return {"Authorization": f"Bearer {token}"}


def mint(client, scope="write", name="test phone"):
    resp = client.post("/v1/sync/tokens", json={"name": name, "scope": scope}, headers=auth())
    assert resp.status_code == 200
    return resp.json()["token"]


def put(client, pid, document, expected, token=ADMIN, note=""):
    return client.put(
        f"/v1/sync/profiles/{pid}",
        json={"doc": document, "note": note},
        headers={**auth(token), "If-Match": f'"{expected}"'},
    )


# --- auth ------------------------------------------------------------------


def test_no_anonymous_access(client):
    assert client.get("/v1/sync/profiles").status_code == 401
    assert client.get("/v1/sync/profiles/kid-a").status_code == 401
    assert client.get("/v1/sync/blobs/" + "0" * 64).status_code == 401
    assert client.get("/v1/sync/profiles", headers=auth("wrong")).status_code == 401


def test_admin_disabled_without_env_token(client, monkeypatch):
    monkeypatch.delenv("HOPESVOICE_ADMIN_TOKEN")
    assert client.get("/v1/sync/profiles", headers=auth("")).status_code == 401
    assert client.post("/v1/sync/tokens", json={"name": "x"}, headers=auth("anything")).status_code == 401


def test_read_token_cannot_write_and_tokens_are_stored_hashed(client, data_root):
    reader = mint(client, "read")
    assert client.get("/v1/sync/profiles", headers=auth(reader)).status_code == 200
    assert put(client, "kid-a", doc(), 0, token=reader).status_code == 403
    assert client.post("/v1/sync/tokens", json={"name": "y"}, headers=auth(reader)).status_code == 403
    stored = (data_root / "sync" / "tokens.json").read_text()
    assert reader not in stored and ADMIN not in stored


def test_revoked_token_stops_working(client):
    token = mint(client)
    tokens = client.get("/v1/sync/tokens", headers=auth()).json()["tokens"]
    assert [t["name"] for t in tokens] == ["test phone"]
    assert client.delete(f"/v1/sync/tokens/{tokens[0]['id']}", headers=auth()).status_code == 200
    assert client.get("/v1/sync/profiles", headers=auth(token)).status_code == 401


# --- versions and ETag -------------------------------------------------------


def test_put_creates_versions_and_requires_if_match(client):
    assert client.put("/v1/sync/profiles/kid-a", json={"doc": doc()}, headers=auth()).status_code == 428
    first = put(client, "kid-a", doc(labels={"a": "One"}), 0)
    assert first.status_code == 200 and first.json()["version"] == 1
    second = put(client, "kid-a", doc(labels={"a": "Two"}), 1, note="rename")
    assert second.json()["version"] == 2
    got = client.get("/v1/sync/profiles/kid-a", headers=auth())
    assert got.headers["etag"] == '"2"'
    assert got.json()["doc"]["overlays"]["labels"] == {"a": "Two"}
    assert got.json()["note"] == "rename"


def test_stale_put_gets_412_with_current_version(client):
    put(client, "kid-a", doc(), 0)
    put(client, "kid-a", doc(labels={"a": "x"}), 1)
    stale = put(client, "kid-a", doc(labels={"a": "y"}), 1)
    assert stale.status_code == 412
    assert stale.json()["current_version"] == 2
    assert client.get("/v1/sync/profiles/kid-a", headers=auth()).json()["doc"]["overlays"]["labels"] == {"a": "x"}


def test_identical_put_does_not_create_a_version(client):
    put(client, "kid-a", doc(labels={"a": "x"}), 0)
    again = put(client, "kid-a", doc(labels={"a": "x"}), 1)
    assert again.status_code == 200 and again.json()["version"] == 1


def test_if_none_match_returns_304_until_something_changes(client):
    put(client, "kid-a", doc(), 0)
    same = client.get("/v1/sync/profiles/kid-a", headers={**auth(), "If-None-Match": '"1"'})
    assert same.status_code == 304 and same.content == b""
    put(client, "kid-a", doc(labels={"a": "x"}), 1)
    changed = client.get("/v1/sync/profiles/kid-a", headers={**auth(), "If-None-Match": '"1"'})
    assert changed.status_code == 200 and changed.json()["version"] == 2


def test_manifest_lists_versions_and_has_its_own_etag(client):
    put(client, "kid-a", doc(), 0)
    put(client, "kid-b", doc(), 0)
    resp = client.get("/v1/sync/profiles", headers=auth())
    assert {p["profile_id"]: p["version"] for p in resp.json()["profiles"]} == {"kid-a": 1, "kid-b": 1}
    tag = resp.headers["etag"]
    assert client.get("/v1/sync/profiles", headers={**auth(), "If-None-Match": tag}).status_code == 304
    put(client, "kid-b", doc(labels={"a": "x"}), 1)
    assert client.get("/v1/sync/profiles", headers={**auth(), "If-None-Match": tag}).status_code == 200


def test_unknown_profile_is_404_and_bad_ids_are_rejected(client):
    assert client.get("/v1/sync/profiles/nobody", headers=auth()).status_code == 404
    assert put(client, "Bad_ID", doc(), 0).status_code == 400
    assert put(client, "..", doc(), 0).status_code in (400, 404)


# --- validation --------------------------------------------------------------


def test_invalid_documents_are_rejected_with_all_errors(client):
    bad = doc(hidden="nope", labels={"a": 1})
    bad["images"] = {"a": "not-a-hash"}
    resp = put(client, "kid-a", bad, 0)
    assert resp.status_code == 422
    errors = resp.json()["detail"]["errors"]
    assert len(errors) == 3
    assert client.get("/v1/sync/profiles/kid-a", headers=auth()).status_code == 404


def test_board_inside_document_is_validated(client):
    broken = copy.deepcopy(BOARD)
    broken["boards"][0]["cells"].append(dict(broken["boards"][0]["cells"][0]))
    d = doc()
    d["board"] = broken
    assert put(client, "kid-a", d, 0).status_code == 422
    d["board"] = BOARD
    assert put(client, "kid-a", d, 0).status_code == 200


# --- history and rollback ------------------------------------------------------


def test_history_and_rollback_restore_older_board_as_new_version(client):
    put(client, "kid-a", doc(labels={"a": "first"}), 0)
    put(client, "kid-a", doc(labels={"a": "second"}), 1)
    history = client.get("/v1/sync/profiles/kid-a/versions", headers=auth()).json()
    assert [v["version"] for v in history["versions"]] == [2, 1]
    old = client.get("/v1/sync/profiles/kid-a/versions/1", headers=auth()).json()
    assert old["doc"]["overlays"]["labels"] == {"a": "first"}
    back = client.post("/v1/sync/profiles/kid-a/rollback", json={"to_version": 1}, headers=auth())
    assert back.status_code == 200 and back.json()["version"] == 3
    head = client.get("/v1/sync/profiles/kid-a", headers=auth()).json()
    assert head["doc"]["overlays"]["labels"] == {"a": "first"}
    assert head["note"] == "rollback to v1"
    assert client.post("/v1/sync/profiles/kid-a/rollback", json={"to_version": 9}, headers=auth()).status_code == 404


# --- edit operations -------------------------------------------------------------


def ops(client, body, pid="kid-a"):
    return client.post(f"/v1/sync/profiles/{pid}/ops", json=body, headers=auth())


def test_overlay_ops_create_one_version_per_request(client):
    resp = ops(client, {"ops": [
        {"op": "set_label", "id": "more", "text": "Again"},
        {"op": "hide", "id": "stop"},
        {"op": "set_style", "id": "more", "background": "#ffd0d0"},
        {"op": "move", "board_key": "", "id": "more", "row": 1, "col": 2},
    ]})
    assert resp.status_code == 200 and resp.json()["version"] == 1
    d = resp.json()["doc"]["overlays"]
    assert d["labels"] == {"more": "Again"}
    assert d["hidden"] == ["stop"]
    assert d["styles"]["more"]["backgroundHex"] == "FFD0D0"
    assert d["positions"][""]["more"] == {"row": 1, "col": 2}
    resp = ops(client, {"ops": [{"op": "unhide", "id": "stop"}, {"op": "set_label", "id": "more", "text": ""}]})
    assert resp.json()["version"] == 2
    assert resp.json()["doc"]["overlays"]["hidden"] == [] and resp.json()["doc"]["overlays"]["labels"] == {}


def test_board_ops_edit_cells_and_stay_valid(client):
    d = doc()
    d["board"] = copy.deepcopy(BOARD)
    put(client, "kid-a", d, 0)
    home = BOARD["profile"]["homeBoard"]
    cells = BOARD["boards"][0]["cells"]
    first = cells[0]["id"]
    free_col = BOARD["profile"]["grid"]["cols"] - 1
    resp = ops(client, {"ops": [
        {"op": "set_cell", "cell": first, "label": "Renamed"},
        {"op": "add_button", "board": home, "cell": {"id": "new-one", "label": "New", "row": 0, "col": free_col}},
    ]})
    assert resp.status_code == 200, resp.text
    board = resp.json()["doc"]["board"]["boards"][0]
    assert next(c for c in board["cells"] if c["id"] == first)["label"] == "Renamed"
    assert any(c["id"] == "new-one" for c in board["cells"])
    resp = ops(client, {"ops": [{"op": "remove_button", "cell": "new-one"}]})
    assert resp.status_code == 200
    assert not any(c["id"] == "new-one" for c in resp.json()["doc"]["board"]["boards"][0]["cells"])


def test_bad_ops_change_nothing(client):
    put(client, "kid-a", doc(), 0)
    assert ops(client, {"ops": [{"op": "nonsense"}]}).status_code == 422
    assert ops(client, {"ops": [{"op": "set_cell", "cell": "x", "label": "y"}]}).status_code == 422
    assert client.get("/v1/sync/profiles/kid-a/versions", headers=auth()).json()["head"] == 1


def test_ops_respect_base_version(client):
    put(client, "kid-a", doc(), 0)
    stale = ops(client, {"ops": [{"op": "hide", "id": "a"}], "base_version": 5})
    assert stale.status_code == 412


# --- pictures -------------------------------------------------------------------


def test_blobs_are_content_addressed_and_authenticated(client):
    data = b"\x89PNG\r\n\x1a\n" + b"synthetic picture"
    sha = hashlib.sha256(data).hexdigest()
    token = mint(client, "write")
    assert client.head(f"/v1/sync/blobs/{sha}", headers=auth(token)).status_code == 404
    assert client.put(f"/v1/sync/blobs/{sha}", content=b"other", headers=auth(token)).status_code == 422
    assert client.put(f"/v1/sync/blobs/{sha}", content=data, headers=auth(token)).status_code == 200
    assert client.head(f"/v1/sync/blobs/{sha}", headers=auth(token)).status_code == 200
    got = client.get(f"/v1/sync/blobs/{sha}", headers=auth(token))
    assert got.content == data and got.headers["etag"] == f'"{sha}"'
    assert client.get(f"/v1/sync/blobs/{sha}").status_code == 401
    assert client.get("/v1/sync/blobs/not-a-hash", headers=auth(token)).status_code == 400
