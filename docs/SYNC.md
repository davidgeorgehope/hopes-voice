# Remote board sync

Edit a child's board on one device (or from the server) and have the others pick it up, without a cable and without ever interrupting the child.

Private by construction: sync is **off** until a caregiver pastes a token. With no token, nothing leaves the device. Boards and photos on the server are only readable with a token.

## What syncs

One document per profile, `bestwishes.sync/v1`:

```json
{
  "format": "bestwishes.sync/v1",
  "board": null,
  "overlays": {
    "hidden": ["slug"],
    "order": { "<board key>": ["id", "id"] },
    "labels": { "<id>": "Label" },
    "positions": { "<board key>": { "<id>": { "row": 0, "col": 1 } } },
    "speak": { "<id>": "Spoken text" },
    "styles": { "<id>": { "backgroundHex": "FCFCF7", "borderHex": "1C1A17" } }
  },
  "images": { "<id>": "<sha256 of the PNG>" }
}
```

- `board` is the imported `bestwishes.board/v1` document (or `null`), validated by the server.
- `overlays` are the caregiver edits: hide, order, rename, move, spoken text, colors.
- `images` lists caregiver photos by content hash. Pictures travel as separate, content-addressed blobs, so an unchanged picture is never uploaded or downloaded twice.

## Server API (`/v1/sync/*`)

Every route needs `Authorization: Bearer <token>`.

| Method | Path | Scope | Notes |
|--------|------|-------|-------|
| GET | `/profiles` | read | Versions of all profiles. `ETag` + `If-None-Match` → 304 |
| GET | `/profiles/{id}` | read | Newest version. `ETag: "<n>"`, `If-None-Match` → 304, 404 if never synced |
| PUT | `/profiles/{id}` | write | Body `{doc, note}`. `If-Match: "<n>"` required (`"0"` creates). 412 + `current_version` when stale |
| GET | `/profiles/{id}/versions` | read | History, newest first |
| GET | `/profiles/{id}/versions/{n}` | read | One full version |
| POST | `/profiles/{id}/rollback` | write | `{to_version}`; writes that document as a **new** version |
| POST | `/profiles/{id}/ops` | write | Edit operations (below). Optional `base_version` |
| PUT/HEAD/GET | `/blobs/{sha256}` | write/read/read | Pictures, verified against the hash |
| POST/GET/DELETE | `/tokens` | admin | Mint (shown once), list, revoke device tokens |

Every accepted change is a new immutable version (`data/sync/profiles/<id>/v000001.json` …), with author and note. History is never rewritten, so rollback is always undoable.

### Tokens

- `HOPESVOICE_ADMIN_TOKEN` (environment, never committed) is the admin token. If it is unset, admin access is off.
- The admin mints per-device tokens: `read` (fetch only) or `write` (also push, upload pictures, roll back). Only a SHA-256 hash is stored.
- Revoke a lost phone with `DELETE /v1/sync/tokens/{id}`.

### Edit operations and the CLI

`POST /profiles/{id}/ops` takes `{"ops": [...]}` and stores the result as one version. Ops: `set_label`, `set_speak`, `hide`, `unhide`, `set_style`, `move` (overlay position), and, when the profile has an imported board, `move_cell`, `set_cell`, `add_button`, `add_folder`, `remove_button`. A bad op changes nothing.

`backend/scripts/hv_sync.py` wraps this (standard library only):

```bash
export HOPESVOICE_TOKEN=...      # admin or device token; never commit it
python3 backend/scripts/hv_sync.py profiles
python3 backend/scripts/hv_sync.py label child1 more "Again"
python3 backend/scripts/hv_sync.py hide child1 stop
python3 backend/scripts/hv_sync.py history child1
python3 backend/scripts/hv_sync.py rollback child1 3
python3 backend/scripts/hv_sync.py mint-token "Caregiver phone" --scope write
```

## How the app syncs

1. **Render from the cache first.** The board always draws from the on-device cache. Sync runs in the background and never blocks a tap, a draw, or launch. Offline simply means "keep using the saved board".
2. **Fetch only what changed.** Each pass asks `GET /profiles` with its last `ETag` (a 304 when nothing moved). Only profiles whose version differs are fetched, with `If-None-Match` on the version. Pictures are fetched by hash, once.
3. **Push edits.** A local edit (any overlay save or a new photo) pushes about 1.5 seconds later with `If-Match` on the version it last saw.
4. **Merge, never overwrite.** On a 412 (or when a newer version arrived), the device merges three ways: the last agreed version, its own state, and the server's. Edits to different buttons both survive; if two devices edit the same entry, the device that is pushing wins that entry; deletes only apply when one side made them. Then it retries.
5. **Never mid-use.** An update from another device is staged on disk. It applies at the next launch, when the caregiver switches profile, or after the board has been idle (default 20 seconds) with nothing in the message bar and no editor open. Edits made while an update waits are merged in, not lost.
6. **Caregiver view.** Settings → Sync shows the status and synced version, lets you sync now, and lists versions to restore. Restore writes the old version as the newest one, then applies it on this device.

State lives next to the cache: `sync-state-<profile>.json` (agreed version, staged update), `sync-blobs/` (downloaded pictures). The token is in the Keychain.

## Development hooks

Launch arguments, same pattern as the other hooks: `-SyncToken <t>` (stores into the Keychain), `-SyncNamespace <n>` (profile ids become `<n>-child1`, so tests never touch real boards), `-SyncBaseURL <url>` (sync host if different from the API host), `-SyncIdleSeconds <s>`, `-SyncPollSeconds <s>`, `-SyncDemoLabel slug=Label`, `-SyncDemoHide slug`, `-OpenSettings` (opens Settings so Sync status can be checked), and the existing `-APIBaseURL`.

## Tests

Backend: `backend/tests/test_sync.py` (auth, versions, ETags, conflicts, rollback, ops, blobs; synthetic data only). iOS: `SyncDocTests` (merge rules) and `SyncEngineTests` (two devices against an in-memory server: edit shows up on the other device, 304s, concurrent merges, offline, bad token, pictures, no echo on apply).
