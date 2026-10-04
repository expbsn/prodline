# Prodline

A SwiftUI iOS app (macOS later) that tracks your projects on a custom build cadence, pulls their metrics via API, and keeps you on deadline with Duolingo-style streaks, XP and haptics.

## Metrics API contract

Each project exposes one endpoint. The app sends `Authorization: Bearer <api key>` (key stored in the Keychain, never in git).

```json
{
  "project": "My App",
  "asOf": "2026-10-04T12:00:00Z",
  "metrics": [
    { "key": "visits", "value": 1234 },
    { "key": "social_views", "value": 560 },
    { "key": "revenue", "value": 56.7, "unit": "USD" }
  ],
  "history": [ { "asOf": "2026-10-03T00:00:00Z", "metrics": [ { "key": "visits", "value": 1100 } ] } ]
}
```
`history` is optional and backfills charts. A project with no endpoint shows sample data.

## Refresh behavior
- Foreground: every 30 s while the app is active, plus immediately on open and on pull-to-refresh.
- Background: opportunistic `BGAppRefresh` (iOS decides the timing).

## Setup
Open `prodline.xcodeproj`, select your team, run on an iPhone simulator/device. iCloud container: `iCloud.expbsn.app.prodline`.
