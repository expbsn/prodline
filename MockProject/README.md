# Mock project server

A stand-in for "a project sending data to Prodline". Python 3 standard library only.

```bash
python3 MockProject/server.py            # http://127.0.0.1:8787
```

| Project | Endpoint | API key | Behavior |
|---|---|---|---|
| Habit Hero | `/projects/habit-hero/metrics` | `hh_live_demo` | Started 9 days ago, fast growth |
| Pixel Quest | `/projects/pixel-quest/metrics` | `pq_live_demo` | Started 23 days ago (observing), social-heavy |
| Side Shop | `/projects/side-shop/metrics` | `ss_live_demo` | Started 2 days ago, high price per sale |
| Flaky App | `/projects/flaky-app/metrics` | `fa_live_demo` | Fails 50% of requests with `503` |

Live traffic is simulated every 2 s, so numbers move on every poll. Hourly history covers the last 7 days and respects `?since=`.

## Poke it

```bash
curl -H "Authorization: Bearer ss_live_demo" localhost:8787/projects/side-shop/metrics
curl -X POST -H "Authorization: Bearer ss_live_demo" -d '{"type":"sale","amount":49}' localhost:8787/projects/side-shop/events
curl -X POST -H "Authorization: Bearer hh_live_demo" -d '{"type":"viral"}' localhost:8787/projects/habit-hero/events
```

Habit Hero's API also returns **goals** (checkpoint 3 + a `signups` metric goal). Side Shop links the mock **GitHub** repo `demo/side-shop` (milestones, issues, README, a 3-day-old last commit), served under `/github`; the demo loader points the app there.

```bash
curl -X POST -H "Authorization: Bearer hh_live_demo" -d '{"type":"goal","id":"onboarding","done":true}' localhost:8787/projects/habit-hero/events
curl -X POST -H "Authorization: Bearer ss_live_demo" -d '{"type":"close_issue","number":12}' localhost:8787/projects/side-shop/events
```

Force failures: `?fail=401|429|500|503`, `?fail=200` (malformed JSON), `?delay=3000`.

## Use it from the app

- **Simulator:** Me → Demo & testing → *Load demo projects* (URL `http://127.0.0.1:8787`).
- **Real iPhone:** run `python3 MockProject/server.py --host 0.0.0.0` and use your Mac's LAN IP (e.g. `http://192.168.1.20:8787`).
- **Debug launch arguments:** `-PRODLINE_DEMO YES` (skip onboarding and load demo projects), `-PRODLINE_TAB plan|insights|me`, `-PRODLINE_OPEN "Pixel Quest"`, `-PRODLINE_CREATE YES`.

## Tests against it

```bash
python3 MockProject/server.py &
TEST_RUNNER_PRODLINE_MOCK_SERVER=http://127.0.0.1:8787 xcodebuild test \
  -project prodline.xcodeproj -scheme prodline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:prodlineTests
```

Without the environment variable, the integration suite is skipped and the unit tests still run.
