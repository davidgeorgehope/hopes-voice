---
name: maintenance-loop
description: Run the Hope's Voice maintenance loop — pick a ready issue, implement a small slice, test, merge to main, and update STATUS.md. Use when doing weekly or unattended work on this AAC app, or when asked to advance milestone-1.
---

# Hope's Voice maintenance loop

## Before you touch code

1. Read `STATUS.md` and `docs/REQUIREMENTS.md`.
2. Confirm you are on the latest `main` and that no open PR is already covering the work.
3. Never commit secrets, `.env` files, `data/`, screenshots that show a child's name, or private family boards (`private/`, `imports/`, `*.private.json`). Those paths are gitignored for a reason.
4. Use **Grok models only** for agent work and for any AI feature in this project. AI calls belong in `backend/`; apps never hold `XAI_API_KEY`.

## Pick work

Pick the top open issue labeled `ready` or, if none is `ready`, `milestone-1`. If several are equally ready, prefer the one that unblocks the first family's private import (configurable settings, importer, parity).

State a short **done-when** on the issue or in your working notes before you write code. Example: "Caregiver can change grid columns per board and the value survives a relaunch."

## Implement

- Work in small vertical slices. One slice should be user-visible or test-gated, not a pile of preparatory refactors.
- Keep SwiftUI for iPhone + iPad. Android work is a separate Kotlin / Compose app against `docs/CONTRACT.md`. Do not start a React Native or Expo rewrite.
- Default profile names stay generic (Child 1 / Child 2). Never add a real child's name to code, docs, tests, issues, or screenshots.
- A real family's board is private. You may read a locally provided import file if the owner gave it to you outside git; you may not copy it into the repo.

## Test

Run what exists, and do not merge red:

- Backend: `cd backend && pytest` (when tests exist; if they do not, say so and do not invent a passing suite).
- iOS: `xcodebuild test -project ios/BestWishes/BestWishes.xcodeproj -scheme BestWishes -destination 'platform=iOS Simulator,name=iPad (A16)'` (adjust the simulator name if needed).
- For UI changes, attach a Simulator screenshot to the PR or issue. No real names, no family photos.
- Android: once the scaffold exists, include a debug build or unit tests.

## Merge and record

- Merge to `main` only when the slice is green. Do not leave hanging pull requests.
- Update `STATUS.md` with three headings: **What shipped**, **What's next**, **One small thing David could contribute** (or "the owner could contribute" if you are writing in the repo's voice). Keep it short.
- Close or comment on the issue with the done-when result.

## Auto-push (when asked)

A launchd watcher on the Mac mini may install a dev build to a reachable iPad with `xcrun devicectl` and retry later if the device is unplugged. If you work on that watcher, use a distinct launchd label and do not disturb other watchers on the machine. Do not spend money on store fees without the owner's approval.
