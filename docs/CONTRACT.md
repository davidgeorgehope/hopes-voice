# Hope's Voice caregiver API contract (iOS)

Base URL: `https://hopesvoice.davidgeorgehope.com`

The host may take a few minutes to go live after DNS or infra changes.

Product lock: iPad never calls xAI. All PECS + TTS generation is server-side.

## Paths

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | `{ "ok": true }` |
| GET | `/v1/board` | Ordered root items (words + folder stubs) |
| GET | `/v1/board?folder_id={slug}` | Ordered children of a folder |
| GET | `/v1/cards` | Flat word-card list (legacy-compatible) |
| GET | `/v1/cards/{slug}` | One word card (or folder stub) |
| POST | `/v1/cards` | Create/generate word card; optional `folder_id` |
| DELETE | `/v1/cards/{slug}` | Delete word card + assets |
| POST | `/v1/folders` | Create folder stub (no xAI) |
| DELETE | `/v1/folders/{slug}` | Delete folder; **children move to root** |
| GET | `/assets/{slug}/image.png` | Card image |
| GET | `/assets/{slug}/audio.mp3` | Card audio |
| GET | `/system/folder.png` | Static folder icon |

## JSON shapes

### GET `/v1/board`

```json
{
  "items": [
    {
      "kind": "folder",
      "word": "Food",
      "name": "Food",
      "slug": "food",
      "image_url": "/system/folder.png",
      "folder_id": null,
      "children": ["juice", "ice-cream"],
      "created_at": "2026-09-16T..."
    },
    {
      "kind": "word",
      "word": "I",
      "slug": "i",
      "image_url": "/assets/i/image.png",
      "audio_url": "/assets/i/audio.mp3",
      "folder_id": null,
      "created_at": "..."
    }
  ],
  "folder_id": null,
  "count": 2
}
```

Inside a folder (`?folder_id=food`), `items` are word cards with `folder_id: "food"`.

### GET `/v1/cards` (flat, old clients)

```json
{
  "cards": [
    {
      "kind": "word",
      "word": "juice",
      "slug": "juice",
      "image_url": "/assets/juice/image.png",
      "audio_url": "/assets/juice/audio.mp3",
      "folder_id": "food",
      "created_at": "..."
    }
  ],
  "count": 1
}
```

Optional fields `kind` and `folder_id` may be present; ignore safely if unused.

### POST `/v1/cards`

Request:

```json
{ "word": "apple", "folder_id": "food" }
```

`folder_id` optional (`null` / omit = root). If the slug already exists, assets are **not** regenerated; membership is updated.

Response includes `kind: "word"` and `folder_id`.

### POST `/v1/folders`

Request:

```json
{ "name": "Food" }
```

Response:

```json
{
  "kind": "folder",
  "word": "Food",
  "name": "Food",
  "slug": "food",
  "image_url": "/system/folder.png",
  "folder_id": null,
  "children": [],
  "created_at": "..."
}
```

### DELETE `/v1/cards/{slug}`

```json
{ "ok": true, "deleted": "bubble" }
```

### DELETE `/v1/folders/{slug}`

Children are moved to root (not deleted):

```json
{
  "ok": true,
  "deleted": "food",
  "moved_to_root": ["juice", "ice-cream"]
}
```

## Persistence

- Word assets: `data/cards/<slug>/{image.png,audio.mp3,meta.json}`
- Board tree: `data/board.json` (`folders`, `card_folder`, `root_order`)
- Folder icon: `data/system/folder.png` → `/system/folder.png`
