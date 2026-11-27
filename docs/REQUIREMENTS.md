# Hope's Voice requirements

This is the durable product brief. Open issues and `STATUS.md` should stay aligned with it.

## Mission

Hope's Voice is a free, $0 AAC (augmentative and alternative communication) app that any family can use. It is an alternative to Proloquo2Go (about $250). A child who needs a talking board should not have to wait on a paid license.

This project is not affiliated with Proloquo2Go or AssistiveWare. We mention Proloquo2Go only as the paid app this is an alternative to.

## Familiar layout, original assets

The app should work mostly like Proloquo2Go in layout and interaction — message bar, grid, folders, core words, color-by-word-type, edit/hide — so a kid who already uses a paid AAC app can switch without relearning.

All symbols are original (AI-generated PECS-style pictures, open-symbol fallbacks, or a family’s own files). We never copy Proloquo2Go, SymbolStix, or other proprietary assets, voices, or branding.

## Stack

- **iOS (iPhone and iPad):** SwiftUI. Keep this native app. Today’s project is iPad-first; iPhone is a universal-target / small-screen layout pass, not a rewrite.
- **Android:** a separate native app in Kotlin and Jetpack Compose. It talks to the same backend API described in `CONTRACT.md`. This is not a React Native or Expo rewrite.
- **Backend:** FastAPI, serving the board API and generating card assets.

## AI

All AI features use the **xAI API (Grok models only)**. Calls always go through the server-side proxy in `backend/`. The iOS and Android apps never hold a key.

The key is never committed to this repo. Self-hosters bring their own `XAI_API_KEY` (see `backend/.env.example`).

## Configurable

A caregiver should be able to configure, without a code change:

- vocabulary and folders
- grid size, per board
- buttons (labels, positions, hide, speak text)
- colors (including a Fitzgerald key / color-by-word-type scheme)
- voice
- message-bar behavior (speak on tap, speak the bar, clear after speak)

The public import format for a full setup is `bestwishes.board/v1` (`IMPORT_FORMAT.md`).

## First milestone

Recreate **one child's** existing Proloquo2Go setup exactly — same buttons, folders, positions, and behavior — for **the first family**.

That setup arrives as a **private** import file. It never enters this repo (`private/`, `*.private.json`, and `imports/` are gitignored). Agents and contributors must not commit family boards, photos, or recordings.

## Store readiness

The goal is to ship on **both** the App Store and Google Play, as a free app:

- a public privacy policy page (no tracking, no ads, kid-safe)
- COPPA / kids-category data handling (no analytics SDKs, no third-party data sharing, account data minimization)
- an accessibility audit (VoiceOver, TalkBack, Switch Control, Dynamic Type, contrast)
- App Store signing and TestFlight
- Play signing and an internal testing track

Paid store fees (including the Google Play developer fee) need the owner’s approval before anyone spends money.

## Maintenance

The project is maintained largely by automated agents (pstack / poteto-mode) with tests and CI as the merge gate. Work merges to `main`. No hanging pull requests. Humans are welcome via issues and PRs.

See `AGENTS.md` and `.agents/skills/maintenance-loop/SKILL.md`.

When a development iPad is reachable from the Mac mini, a watcher should auto-push dev builds with `xcrun devicectl` and retry later if the device is unplugged. That watcher must use a distinct launchd label and must not disturb other watchers on the machine.


## Name and identifiers

The product name is **Hope's Voice**. The home-screen display name and user-facing copy use that name.

- GitHub repo: `https://github.com/davidgeorgehope/hopes-voice`
- iOS bundle ID: `com.davidgeorgehope.hopesvoice` (tests: `com.davidgeorgehope.hopesvoice.tests`)
- Production API: `https://hopesvoice.davidgeorgehope.com` — this is the only production host. The iOS app reads it from the single constant `APIClient.productionBaseURL`. The host may take a few minutes to go live after DNS or infra changes.
- Xcode project, target, and scheme names remain `BestWishes` (path `ios/BestWishes/`) so GitHub Actions (`ios.yml`) and the Mac mini auto-push script keep working.
- The board import format identifier remains `bestwishes.board/v1` for compatibility. On-disk cache folders and UserDefaults keys that already use a `bestwishes.` prefix are left as-is so existing installs do not lose data.
- Some server paths on the existing host (for example `/etc/bestwishes/env`) may still use the old internal name until infra is renamed.

## Privacy in this repository

Never publish a child’s name, photo, or recording. Default on-device profile names are generic (Child 1 / Child 2). Screenshots that might show a real profile name stay out of git.
