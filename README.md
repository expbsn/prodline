# Prodline

A SwiftUI iOS app (macOS later) for people who ship a project every cycle. You set your own rhythm (for example, 2 weeks building, 4 weeks observing, a new project every 2 weeks). Prodline turns that rhythm into weekday checkpoints, keeps you on deadline with streaks, XP and haptics, and pulls each project's numbers (visits, social views, revenue, custom metrics) through a small API.

## Design

- **Neutral chrome, colorful projects.** The app UI is ink on light gray. Each project has its own accent, either extracted from its square cover photo or picked by you. The accent carries through the project's card, buttons, charts and deadlines.
- **Projects are playing cards** (5:7) in a 3D carousel. The same card appears in the carousel, the create flow preview and the detail hero.
- Custom floating tab bar, chunky 3D-press buttons, sliders that tick, and confetti on deadlines.
- Fonts: **Afacad Flux** (variable) for prominent text, SF Pro for body text.
- Light mode only, portrait only on iPhone.

## Structure

```
prodline/
  Design/     Theme (palette, Accent, fonts), components, ProjectCard, TabBar, ImageTools (color extraction)
  Models/     SwiftData models (CloudKit-compatible)
  Services/   Metrics API client, DataRefresher (polling/backoff), ScheduleEngine, DemoData
  Views/      Home (carousel), Plan, Insights, Me/Scheme, Create flow, Project detail, Connection
prodlineTests/  Unit tests, a 12-week schedule backtest, and mock-server integration tests
MockProject/    Local server that simulates projects sending data
docs/API.md     The metrics API contract
```

## Data & sync

- SwiftData syncs through the private CloudKit database (`iCloud.expbsn.app.prodline`) and falls back to local storage when iCloud is unavailable.
- API keys live in the Keychain (iCloud Keychain), never in synced records.
- Polling: every 30 s in the foreground, plus on open and on pull-to-refresh; BGAppRefresh in the background; exponential backoff for failing endpoints. See [docs/API.md](docs/API.md).

## Run

1. Open `prodline.xcodeproj` and run on an iPhone simulator.
2. Optional: `python3 MockProject/server.py`, then Me → *Load demo projects* (see [MockProject/README.md](MockProject/README.md)).

## Test

```bash
python3 MockProject/server.py &
TEST_RUNNER_PRODLINE_MOCK_SERVER=http://127.0.0.1:8787 xcodebuild test -project prodline.xcodeproj \
  -scheme prodline -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:prodlineTests
```
