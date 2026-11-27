# Status

Short note for weekly check-ins. Agents should update this when something ships.

## What shipped

- The product is now **Hope's Voice**. The public repo is [davidgeorgehope/hopes-voice](https://github.com/davidgeorgehope/hopes-voice) (the previous repo URL redirects here), MIT-licensed, with the existing SwiftUI iPad app and the FastAPI backend (no secrets, no family data, no screenshots).
- Home-screen display name and user-facing copy say Hope's Voice. The iOS bundle ID is `com.davidgeorgehope.hopesvoice` (tests: `com.davidgeorgehope.hopesvoice.tests`).
- Production API host is [hopesvoice.davidgeorgehope.com](https://hopesvoice.davidgeorgehope.com), configured in the app as the single constant `APIClient.productionBaseURL`. The host may take a few minutes to go live via infra. Apps never hold an xAI key; the backend generates original PECS pictures and spoken audio through the xAI API (Grok models only).
- iPad app features already in the tree: message bar (speak / clear / backspace), kid vs caregiver mode, folders, edit/hide, offline speech from cache, 2/3/4 column grid, sticky core words (I / want / more / help / stop / go), multiple child profiles (defaults: Child 1 / Child 2), reorder/rename, recents, caregiver search, and caregiver voice-add via on-device speech recognition.
- Docs: mission and requirements, API contract, USB device-run notes, board import format (`bestwishes.board/v1`), contributing guide, and a maintenance-loop skill.
- Product stack is decided: keep SwiftUI for iPhone + iPad; build Android separately in Kotlin + Jetpack Compose against the same API.
- GitHub Actions CI runs on `main` for [backend](https://github.com/davidgeorgehope/hopes-voice/actions/workflows/backend.yml) (`pytest`, xAI mocked) and [ios](https://github.com/davidgeorgehope/hopes-voice/actions/workflows/ios.yml) (Xcode, iPad (A16) simulator, `CODE_SIGNING_ALLOWED=NO`). Badges are on the README. The Xcode project, target, and scheme remain `BestWishes` so CI and the Mac mini auto-push script stay wired.

## What's next

- Milestone 1: configurable settings (grid, colors, voice, message bar), a validated board importer, and recreating one child's existing setup for the first family from a *private* import file that never enters this repo.
- iPhone support (universal target, small-screen layout) and an Android app scaffold.
- An Android CI build job once the Kotlin/Compose scaffold exists.
- Store-readiness work for a free App Store and Google Play listing (privacy policy, COPPA / kid-safe handling, accessibility, signing). Paid fees need owner approval.
- Folder-from-prompt generation, and an auto-push-to-device watcher on the Mac mini when an iPad is reachable.

## One small thing David could contribute

Start a *private* (not in git) transcription of the first family's existing board into the `bestwishes.board/v1` format in `docs/IMPORT_FORMAT.md` — same buttons, folders, and positions. That file is what milestone 1 will import. A USB debug run on the family's iPad, with notes on anything that feels unlike the familiar layout, is also a huge help.
