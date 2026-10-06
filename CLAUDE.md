# Prodline

SwiftUI iOS app (iOS 26, SwiftData + CloudKit) that tracks side projects: metrics from each project's API, checkpoints on a build/observe schedule, and goals that complete themselves.

## Keep prodline.json current

`prodline.json` in the repo root is this project's plan. The Prodline app reads it from GitHub and shows these goals on its checkpoints, ticking them off as they change here. Treat updating it as part of finishing any task:

- When a change completes a goal, set `"done": true` **in the same commit** as the work. Never delete goals that are done.
- If you do meaningful work that no goal covers, add a goal for it (and mark it done if it's finished).
- Keep `id`s stable, lowercase-with-dashes; never reuse an id for a different goal. Change a goal's title or `due` rather than adding a near-duplicate.
- Place checkpoints and goals with `"day": N`, counted from the project's start in the app (day 1 = Oct 5, 2026 for Prodline). A goal lands on the first checkpoint on or after its day. Keep the file sorted by day.
- 1–4 goals per checkpoint. Titles are short, concrete and start with a verb ("Add Stripe checkout"), never vague activities.
- `"checkpoints": [{"day": N, "title": "..."}]` are the project's checkpoints in the app, exactly these. Add one when a new phase of work starts.
- Optional `"metric": {"key": "signups", "target": 500}` for goals reached by a number rather than code.
- The file must stay valid JSON. Check with `python3 -m json.tool prodline.json > /dev/null`.

Format details: `docs/API.md`, section "prodline.json in the repo".

## Metrics feed

`.github/workflows/metrics.yml` runs `tools/prodline_metrics.py` and force-pushes `metrics.json` to the `metrics` branch. In the app, the Prodline project's endpoint is `https://raw.githubusercontent.com/expbsn/prodline/metrics/metrics.json` (no key). Keep the script's output in the metrics API format (`docs/API.md`).

## Build and test

```bash
xcodebuild -project prodline.xcodeproj -scheme prodline -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
python3 MockProject/server.py &   # needed by the integration tests
TEST_RUNNER_PRODLINE_MOCK_SERVER=http://127.0.0.1:8787 xcodebuild test -project prodline.xcodeproj -scheme prodline -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Add `TEST_RUNNER_PRODLINE_REAL_GITHUB=expbsn/prodline` to also run the backtest against this repo on GitHub (it reads this prodline.json).

DEBUG launch arguments for jumping straight to a screen: `-PRODLINE_DEMO YES`, `-PRODLINE_TAB plan|insights|me`, `-PRODLINE_OPEN "Project name"`, `-PRODLINE_CREATE YES`, `-PRODLINE_NOLAUNCH YES` (skip the splash), `-PRODLINE_BANNER YES`, `-PRODLINE_SHEET widgets|connection|verdict|targets|share` (the last four on the project opened with `-PRODLINE_OPEN`), `-PRODLINE_REVIEW YES` (weekly review), `-PRODLINE_LIVE YES` (sample deadline Live Activity).

## Conventions

- Bright theme only, portrait only. Colors, fonts and the chunky button styles live in `prodline/Design/`; reuse them instead of new one-off styling.
- The tab bar and other chrome stay neutral; project color comes from `\.accent`.
- Dash card geometry is shared through `DashLayout`. When the card's size or position changes on Dash, the project detail screen must match.
- Secrets (API keys, GitHub tokens) go in the Keychain, never in SwiftData or the repo.
- `Shared/` is compiled into both the app and the `ProdlineWidgets` extension (design primitives, widget data and widget views). The app writes `WidgetData` to the App Group `group.expbsn.app.prodline` via `WidgetPublisher` after each refresh; widgets only read it. Me → Widgets previews the same views (`-PRODLINE_SHEET widgets` opens the gallery).
- The logo is drawn in `design/make_logo.swift` and `prodline/Design/LaunchView.swift` (`LogoGeometry`); keep the two in sync.
