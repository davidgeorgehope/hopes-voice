# Status

Short note for weekly check-ins. Agents should update this when something ships.

## What shipped

- The product is now **Hope's Voice**. The public repo is [davidgeorgehope/hopes-voice](https://github.com/davidgeorgehope/hopes-voice) (the previous repo URL redirects here), MIT-licensed, with the existing SwiftUI iPad app and the FastAPI backend (no secrets, no family data, no screenshots).
- Home-screen display name and user-facing copy say Hope's Voice. The iOS bundle ID is `com.davidgeorgehope.hopesvoice` (tests: `com.davidgeorgehope.hopesvoice.tests`).
- Production API host is [hopesvoice.davidgeorgehope.com](https://hopesvoice.davidgeorgehope.com), configured in the app as the single constant `APIClient.productionBaseURL`. Apps never hold an xAI key; the backend generates original PECS pictures and spoken audio through the xAI API (Grok models only).
- Card pictures now fill their cells. The app trims near-white margins at render time; the backend does the same (and re-pads to a ~6% margin) on newly generated cards, and the generation prompt asks for the subject to fill ~85% of the frame. A one-off script `backend/scripts/retrim_card_images.py` can re-process existing images in the data dir after backing up originals.
- iPhone layout no longer clips: the message bar, core-words row, and board grid all fit the screen width (including a 4-column grid). The sentence bar keeps a usable chip well between Speak, Back, and Clear.
- iPad app features already in the tree: message bar (speak / clear / backspace), kid vs caregiver mode, folders, edit/hide, offline speech from cache, 2/3/4 column grid, sticky core words (I / want / more / help / stop / go), multiple child profiles (defaults: Child 1 / Child 2), reorder/rename, recents, caregiver search, and caregiver voice-add via on-device speech recognition.
- Docs: mission and requirements (including the Proloquo2Go-familiar editor workflow), API contract, USB device-run notes, board import format (`bestwishes.board/v1`), contributing guide, store listing copy, and a maintenance-loop skill.
- Product stack is decided: keep SwiftUI for iPhone + iPad; build Android separately in Kotlin + Jetpack Compose against the same API.
- GitHub Actions CI runs on `main` for [backend](https://github.com/davidgeorgehope/hopes-voice/actions/workflows/backend.yml) (`pytest`, xAI mocked) and [ios](https://github.com/davidgeorgehope/hopes-voice/actions/workflows/ios.yml) (Xcode, iPad (A16) simulator, `CODE_SIGNING_ALLOWED=NO`). Badges are on the README. The Xcode project, target, and scheme remain `BestWishes` so CI and the Mac mini auto-push script stay wired.

## What's next

- Proloquo2Go-familiar workflow (layout and interaction only, original assets): a discoverable kid-proof Edit / lock control in the toolbar; in Edit, tap a button to open a button editor (label, spoken text, picture generate/photo, colors, folder link); add a button into an empty grid cell; a fixed rows × columns grid (default 4×6 on iPad, smaller on iPhone); message-bar chips and tap-to-speak; visually distinct folder buttons; Fitzgerald part-of-speech colors. See issues #1, #7, and #8, and `docs/REQUIREMENTS.md`.
- Milestone 1: configurable settings (grid, colors, voice, message bar), a validated board importer, and recreating one child's existing setup for the first family from a *private* import file that never enters this repo.
- An Android app scaffold and an Android CI build job once the Kotlin/Compose scaffold exists.
- Store-readiness work for a free App Store and Google Play listing (privacy policy, COPPA / kid-safe handling, accessibility, signing). Paid fees need owner approval.

## One small thing David could contribute

Start a *private* (not in git) transcription of the first family's existing board into the `bestwishes.board/v1` format in `docs/IMPORT_FORMAT.md` — same buttons, folders, and positions. That file is what milestone 1 will import. A USB debug run on the family's iPad, with notes on anything that feels unlike the familiar layout, is also a huge help.
