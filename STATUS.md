# Status

Short note for weekly check-ins. Agents should update this when something ships.

## What shipped

- Public repo for BestWishes, MIT-licensed, with the existing SwiftUI iPad app and the FastAPI backend (no secrets, no family data, no screenshots).
- iPad app features already in the tree: message bar (speak / clear / backspace), kid vs caregiver mode, folders, edit/hide, offline speech from cache, 2/3/4 column grid, sticky core words (I / want / more / help / stop / go), multiple child profiles (defaults: Child 1 / Child 2), reorder/rename, recents, caregiver search, and caregiver voice-add via on-device speech recognition.
- Backend API at bestwishes.love (and runnable locally) that generates original PECS pictures and spoken audio through the xAI API (Grok models only). Apps never hold a key.
- Docs: mission and requirements, API contract, USB device-run notes, board import format (`bestwishes.board/v1`), contributing guide, and a maintenance-loop skill.
- Product stack is decided: keep SwiftUI for iPhone + iPad; build Android separately in Kotlin + Jetpack Compose against the same API.

## What's next

- Milestone 1: configurable settings (grid, colors, voice, message bar), a validated board importer, and recreating one child's existing setup for the first family from a *private* import file that never enters this repo.
- iPhone support (universal target, small-screen layout) and an Android app scaffold.
- GitHub Actions CI for backend tests, iOS `xcodebuild test`, and the Android build (follow-up; not in the tree yet).
- Store-readiness work for a free App Store and Google Play listing (privacy policy, COPPA / kid-safe handling, accessibility, signing). Paid fees need owner approval.
- Folder-from-prompt generation, and an auto-push-to-device watcher on the Mac mini when an iPad is reachable.

## One small thing David could contribute

Start a *private* (not in git) transcription of the first family's existing board into the `bestwishes.board/v1` format in `docs/IMPORT_FORMAT.md` — same buttons, folders, and positions. That file is what milestone 1 will import. A USB debug run on the family's iPad, with notes on anything that feels unlike the familiar layout, is also a huge help.
