# Contributing to BestWishes

Thank you for helping make a free AAC app that families can actually use.

## Start with an issue

Pick an open issue, especially `good first issue`, `help wanted`, or `milestone-1`. If you want to do something that is not filed yet, open an issue first so the work stays visible.

The product brief is [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md). The API contract is [`docs/CONTRACT.md`](docs/CONTRACT.md).

## How we merge

- Work in a branch, then open a pull request into `main`.
- Merge only when tests are green. CI is the gate once GitHub Actions lands; until then, run what you can locally and say what you ran.
- Do not leave hanging pull requests. If work is blocked, say so on the issue and close or convert the PR rather than parking it.
- Keep commits focused. Prefer small vertical slices over large mixed diffs.

## Tests

- **iOS:** `xcodebuild test -project ios/BestWishes/BestWishes.xcodeproj -scheme BestWishes -destination 'platform=iOS Simulator,name=iPad (A16)'` (adjust the simulator name if needed).
- **Backend:** add and run `pytest` under `backend/` as tests land.
- **Android:** once the scaffold exists, include a debug build / unit tests in the PR.
- For UI changes on iOS, attach a Simulator screenshot in the PR (no real child names or family photos).

## Privacy and secrets

- Never commit `/etc/bestwishes/env`, `.env` files, API keys, credentials, `data/`, `DerivedData`, build output, or screenshots that show a child's name.
- Never commit a family's board, photos, or recordings. Private import files stay under `private/`, `imports/`, or `*.private.json`, all of which are gitignored. The format itself (`docs/IMPORT_FORMAT.md`) is public.
- Default profile names in the app are Child 1 and Child 2. Do not add real children's names to code, docs, tests, or issues.
- AI features use the xAI API (Grok models only) from `backend/`. Apps never hold `XAI_API_KEY`. Self-hosters bring their own key.

## Tone and product

This is a communication tool for kids. Keep the caregiver UI calm and the kid board uncluttered. We copy familiar AAC *interaction*, not anyone else's symbols, voices, or branding. Do not claim affiliation with Proloquo2Go or AssistiveWare.

## License

By contributing, you agree that your work is licensed under the MIT License, with copyright held by David Hope.
