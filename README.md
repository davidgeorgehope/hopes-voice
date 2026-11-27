# BestWishes

A free, open-source AAC (augmentative and alternative communication) app for families. BestWishes is a $0 alternative to Proloquo2Go (about $250). A child who needs a talking board should not have to wait on a paid license.

Layout and interaction follow familiar AAC patterns — a message bar, a grid of buttons, folders, core words, and color-by-word-type — so a kid who already uses a paid AAC app can switch without relearning. All symbols are original AI-generated PECS-style pictures. This project is not affiliated with Proloquo2Go or AssistiveWare; we mention Proloquo2Go only as the paid app this is an alternative to.

The full brief lives in [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md). A short weekly status note is in [`STATUS.md`](STATUS.md).

## What works today

The iOS app is a SwiftUI project that currently targets **iPad** (iPhone support is next). Caregivers can already:

- Build a sentence on the message bar, then **Speak**, clear, or backspace
- Switch **kid** and **caregiver** mode (long-press the title to unlock caregiver tools; kid mode stays simple)
- Add **folders**, hide or edit cards, reorder cells, and rename display labels
- **Speak offline** from the on-device cache after the board has been warmed once
- Choose a **2 / 3 / 4 column** grid
- Keep a sticky **core words** row: I, want, more, help, stop, go
- Use **multiple child profiles** (defaults are Child 1 and Child 2; caregivers will be able to rename them)
- See **recents**, **search** the open board (caregiver), and **voice-add** a card (caregiver only, on-device speech recognition; kid mode has no microphone)

The live API at [bestwishes.love](https://bestwishes.love) serves the board and generates new cards.

## Architecture

```
[ iOS SwiftUI app ]  --HTTPS--  [ backend (FastAPI) ]  --  [ xAI API, Grok models ]
[ Android (planned) ]              generates pictures + TTS
```

The apps never call an AI provider and never hold a key. When a caregiver adds a word, the app `POST`s `{ "word": "bananas" }` to the backend. The server creates an original picture and a spoken MP3, then the app caches those files on the device so Speak still works offline.

Self-hosters run `backend/` themselves and bring their own `XAI_API_KEY`. The key is never committed to this repo. See [`backend/.env.example`](backend/.env.example).

## Stack

This is decided, not under consideration:

- **iPhone and iPad:** the existing **SwiftUI** app, kept native. Today it is iPad-only; iPhone is a universal-target and small-screen layout pass.
- **Android:** a **separate native** app in **Kotlin and Jetpack Compose**, talking to the same backend API in [`docs/CONTRACT.md`](docs/CONTRACT.md). There is no React Native or Expo rewrite.
- **Backend:** FastAPI on `bestwishes.love` (or your own host).

## How to run

### iOS Simulator

On a Mac with Xcode 16+ and an iOS 18 simulator:

```bash
open ios/BestWishes/BestWishes.xcodeproj
```

Pick the **BestWishes** scheme and an iPad simulator, then press ⌘R. Point the app at `https://bestwishes.love`, or at a local backend if you change the base URL.

To run tests:

```bash
xcodebuild test \
  -project ios/BestWishes/BestWishes.xcodeproj \
  -scheme BestWishes \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

The Simulator has no microphone, so live caregiver dictation needs a real iPad. USB install notes are in [`docs/DEVICE.md`](docs/DEVICE.md).

### Backend locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export XAI_API_KEY=...   # your key; never commit it
uvicorn app.main:app --host 0.0.0.0 --port 8080
```

More detail is in [`backend/README.md`](backend/README.md).

## Roadmap

Work is tracked as GitHub issues. The near-term list:

1. **Milestone 1** — configurable settings, a `bestwishes.board/v1` importer, and using a *private* import file (never in this repo) to recreate one child's existing setup for the first family.
2. **iPhone support** in the SwiftUI app (universal target, layouts for small screens).
3. **Android** scaffold in Kotlin / Compose against the same API, then feature parity.
4. **CI** (GitHub Actions for backend tests, iOS `xcodebuild test`, and the Android build) — coming in a follow-up; not in the tree yet.
5. **Store readiness** for a free App Store and Google Play listing (privacy policy, COPPA / kid-safe data handling, accessibility, signing). Paid fees need the owner's approval.
6. Folder-from-prompt generation, rate limits so free AI stays sustainable, open-symbol fallbacks, on-device TTS, localization, and an auto-push-to-device watcher.

See also [`docs/IMPORT_FORMAT.md`](docs/IMPORT_FORMAT.md).

## How to contribute

Please read [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues labeled `good first issue` and `help wanted` are a good place to start. Open a pull request against `main`, keep secrets and private family data out of git, and expect tests to be the merge gate.

## Maintenance

This project is maintained largely by automated agents (see [`AGENTS.md`](AGENTS.md)), with tests and CI as the gate. Humans are welcome via issues and pull requests. Weekly status is recorded in [`STATUS.md`](STATUS.md): what shipped, what's next, and one small thing the owner could contribute.

## License

[MIT](LICENSE). Copyright © 2026 David Hope.
