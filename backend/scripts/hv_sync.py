#!/usr/bin/env python3
"""Small CLI for the board sync API. Standard library only.

Environment (never commit values):
  HOPESVOICE_URL    default https://hopesvoice.davidgeorgehope.com
  HOPESVOICE_TOKEN  admin token or a write/read device token

Examples:
  hv_sync.py profiles
  hv_sync.py show child1
  hv_sync.py history child1
  hv_sync.py label child1 more "Again"
  hv_sync.py hide child1 stop
  hv_sync.py style child1 more --background FFD0D0
  hv_sync.py move child1 more 1 2 [--board-key folder-id]
  hv_sync.py rollback child1 3
  hv_sync.py mint-token "Dad's phone" --scope write
  hv_sync.py ops child1 '[{"op":"hide","id":"stop"}]'
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("HOPESVOICE_URL", "https://hopesvoice.davidgeorgehope.com").rstrip("/")


def call(method: str, path: str, body=None):
    token = os.environ.get("HOPESVOICE_TOKEN", "").strip()
    if not token:
        sys.exit("Set HOPESVOICE_TOKEN (admin or device token).")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as err:
        sys.exit(f"HTTP {err.code}: {err.read().decode()[:600]}")


def run_ops(profile: str, ops: list[dict], note: str = ""):
    result = call("POST", f"/v1/sync/profiles/{profile}/ops", {"ops": ops, "note": note})
    print(f"{profile} is now version {result['version']} ({result['note']})")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("profiles")
    for name in ("show", "history"):
        sub.add_parser(name).add_argument("profile")
    s = sub.add_parser("label")
    s.add_argument("profile"); s.add_argument("id"); s.add_argument("text")
    s = sub.add_parser("speak")
    s.add_argument("profile"); s.add_argument("id"); s.add_argument("text")
    for name in ("hide", "unhide"):
        s = sub.add_parser(name)
        s.add_argument("profile"); s.add_argument("id")
    s = sub.add_parser("style")
    s.add_argument("profile"); s.add_argument("id")
    s.add_argument("--background"); s.add_argument("--border")
    s = sub.add_parser("move")
    s.add_argument("profile"); s.add_argument("id"); s.add_argument("row", type=int); s.add_argument("col", type=int)
    s.add_argument("--board-key", default="")
    s = sub.add_parser("rollback")
    s.add_argument("profile"); s.add_argument("version", type=int)
    s = sub.add_parser("ops")
    s.add_argument("profile"); s.add_argument("json")
    s = sub.add_parser("mint-token")
    s.add_argument("name"); s.add_argument("--scope", default="write", choices=["read", "write"])
    sub.add_parser("tokens")
    a = p.parse_args()

    if a.cmd == "profiles":
        for item in call("GET", "/v1/sync/profiles")["profiles"]:
            print(f"{item['profile_id']}\tv{item['version']}\t{item['updated_at']}\t{item['author']}\t{item['note']}")
    elif a.cmd == "show":
        print(json.dumps(call("GET", f"/v1/sync/profiles/{a.profile}"), indent=1))
    elif a.cmd == "history":
        for v in call("GET", f"/v1/sync/profiles/{a.profile}/versions")["versions"]:
            print(f"v{v['version']}\t{v['updated_at']}\t{v['author']}\t{v['note']}")
    elif a.cmd == "label":
        run_ops(a.profile, [{"op": "set_label", "id": a.id, "text": a.text}])
    elif a.cmd == "speak":
        run_ops(a.profile, [{"op": "set_speak", "id": a.id, "text": a.text}])
    elif a.cmd in ("hide", "unhide"):
        run_ops(a.profile, [{"op": a.cmd, "id": a.id}])
    elif a.cmd == "style":
        run_ops(a.profile, [{"op": "set_style", "id": a.id, "background": a.background, "border": a.border}])
    elif a.cmd == "move":
        run_ops(a.profile, [{"op": "move", "board_key": a.board_key, "id": a.id, "row": a.row, "col": a.col}])
    elif a.cmd == "rollback":
        r = call("POST", f"/v1/sync/profiles/{a.profile}/rollback", {"to_version": a.version})
        print(f"{a.profile} is now version {r['version']} ({r['note']})")
    elif a.cmd == "ops":
        run_ops(a.profile, json.loads(a.json))
    elif a.cmd == "mint-token":
        r = call("POST", "/v1/sync/tokens", {"name": a.name, "scope": a.scope})
        print(f"id={r['id']} scope={r['scope']}\ntoken (shown once): {r['token']}")
    elif a.cmd == "tokens":
        for t in call("GET", "/v1/sync/tokens")["tokens"]:
            print(f"{t['id']}\t{t['scope']}\t{t['name']}\t{t['created_at']}")


if __name__ == "__main__":
    main()
