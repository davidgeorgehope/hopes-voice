# BestWishes backend

FastAPI service that serves the caregiver board API and generates PECS-style card assets.

- **Pictures** — xAI image generation (Grok models, 1:1, no text in the image)
- **Spoken audio** — xAI TTS (Eve voice MP3)

The iOS and Android apps only play and cache these assets. They never call xAI and never hold a key. All AI stays in this process.

The public API contract is in [`docs/CONTRACT.md`](../docs/CONTRACT.md). The production hostname is `https://bestwishes.love`.

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Required environment variable (name only; never commit the value):

```bash
export XAI_API_KEY=...
```

See `.env.example`. Self-hosters bring their own xAI key. An optional local fallback file is `~/.config/xai/credentials.env` containing a `XAI_API_KEY=` line; prefer the environment variable.

Generated assets are written under `backend/data/` (gitignored). Do not commit that directory.

## Run

```bash
cd backend
source .venv/bin/activate
export XAI_API_KEY=...
uvicorn app.main:app --host 0.0.0.0 --port 8080
```

Health check: `curl -sS http://127.0.0.1:8080/health`

### Example: create an ice cream card

```bash
curl -sS -X POST http://127.0.0.1:8080/v1/cards \
  -H 'Content-Type: application/json' \
  -d '{"word":"ice cream"}'
```

### One-shot without the server

```bash
cd backend
source .venv/bin/activate
export XAI_API_KEY=...
python scripts/generate_card.py "ice cream"
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | `{ "ok": true }` |
| GET | `/v1/board` | Ordered root board (words + folders) |
| POST | `/v1/cards` | Generate image + TTS; optional `folder_id` |
| GET | `/v1/cards` | Flat word-card list |
| GET | `/v1/cards/{slug}` | Card metadata |
| DELETE | `/v1/cards/{slug}` | Delete word card + assets |
| POST | `/v1/folders` | Create folder stub |
| DELETE | `/v1/folders/{slug}` | Delete folder (children move to root) |
| GET | `/assets/{slug}/image.png` | Static image |
| GET | `/assets/{slug}/audio.mp3` | Static audio |
| GET | `/system/folder.png` | Static folder icon |

See `docs/CONTRACT.md` for JSON shapes.
