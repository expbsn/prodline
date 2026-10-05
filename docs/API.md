# Prodline Metrics API

Every project you track exposes **one HTTPS endpoint**. Prodline polls it; your project never needs to know about the app.

## Request

```
GET <endpoint>?since=<ISO-8601>
Authorization: Bearer <api key>
Accept: application/json
User-Agent: Prodline/1.0
```

- `since` (optional): the timestamp of the newest data point Prodline already has. Return only `history` points **after** it. Omitted on the first sync.
- The API key is created by you, entered in the app, and stored in the iOS Keychain (synced via iCloud Keychain). It is never written to SwiftData/CloudKit records.

## Response `200 OK`

```json
{
  "schemaVersion": 1,
  "project": "Habit Hero",
  "asOf": "2026-10-04T12:00:00.000Z",
  "metrics": [
    { "key": "visits",       "value": 8849 },
    { "key": "social_views", "value": 21114 },
    { "key": "revenue",      "value": 529.89, "unit": "USD" },
    { "key": "signups",      "value": 398 }
  ],
  "history": [
    { "asOf": "2026-10-04T11:00:00Z", "metrics": [ { "key": "visits", "value": 8790 } ] }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `asOf` | yes | ISO-8601, with or without fractional seconds. |
| `metrics` | yes | **Cumulative totals** (all-time), not deltas. |
| `metrics[].key` | yes | `visits`, `social_views`, `revenue` are built in. Any other key is shown as a custom metric. |
| `metrics[].unit` | no | Informational. Revenue is displayed as USD. |
| `history` | no | Points for charts, ideally hourly. Prodline de-duplicates by minute, so re-sending is harmless. |
| `schemaVersion` | no | Currently `1`. |

## Goals (optional)

Projects can tell Prodline what has to be done by each checkpoint. Add a `goals` array to the same response:

```json
"goals": [
  { "id": "onboarding", "title": "Onboarding flow live", "checkpoint": 3, "done": false },
  { "id": "launch-post", "title": "Launch post published", "due": "2026-10-08T00:00:00Z", "url": "https://…" },
  { "id": "signups-500", "title": "500 signups", "checkpoint": 4, "metric": { "key": "signups", "target": 500 } }
]
```

| Field | Notes |
|---|---|
| `id` | Stable per goal. Used to update goals between polls. |
| `checkpoint` | 1-based position in the project's deadline list (checkpoints, then "Ship it", then "Traction review"). |
| `due` | Alternative to `checkpoint`: the goal lands on the first deadline on or after this date. Neither → next open deadline. |
| `done` | Ticks the goal off. |
| `metric` | Ticks itself when the metric (built-in or custom key) reaches `target`. |

- When `goals` is present it is the full list: goals missing from it are removed (unless already done).
- A checkpoint whose goals are all done **completes automatically** (XP and streak as if tapped).
- Goals from your API or GitHub replace on-device suggestions on the same checkpoint.

### Other goal sources

- **prodline.json in the repo:** link a GitHub repo and add `prodline.json` at its root — `{"version": 1, "goals": [...]}` with the same goal fields as above (`due` may also be a plain `YYYY-MM-DD`). Read every 10 min. A missing file clears its open goals; an invalid one is reported and existing goals are kept. Optional `"checkpoints": [{"checkpoint": 1, "title": "Accounts"}]` (or `"due"` instead of `"checkpoint"`) names checkpoints; names set by hand in the app win. When the file exists it is the plan: on-device suggestions are removed and not offered. This is the easiest way to let Claude Code plan checkpoints and tick goals as it ships: the guide in the app has a copyable instruction for Claude Code / CLAUDE.md.
- **GitHub:** link a repo on the project. Issues in a GitHub milestone, or labeled `prodline`, become goals and tick off when closed. A milestone's due date picks the checkpoint; without one, the Nth milestone maps to the Nth checkpoint. Pull requests are ignored. Repos are read every 10 min (token optional, for private repos / higher rate limit; stored in the Keychain). The README and open issues also feed suggestions, and a quiet repo (no commits for 2+ days) right before a checkpoint triggers a nudge.
- **On-device suggestions:** with Apple Intelligence, Prodline drafts 1–3 goals per checkpoint from the name, description and linked repo, both in the create flow and from the project screen. Nothing leaves the device. Without Apple Intelligence (and without API/GitHub goals) checkpoints stay plain and are ticked by hand.
- **Traction targets:** during the observe phase the "Traction review" gets stretch targets for visits (and revenue, if any) based on the last week's pace; they tick themselves.

## Errors

| Status | How Prodline reacts |
|---|---|
| `401` / `403` | Shows “API key rejected”, backs off. |
| `404` | Shows “Endpoint not found”, backs off. |
| `429` | Honors `Retry-After` (seconds). |
| `5xx`, timeouts, offline | Exponential backoff: 30 s, 60 s, 120 s … capped at 15 min. |
| Invalid JSON / missing fields | Shows which field is wrong, backs off. |

## Polling behavior

- **App in foreground:** every **30 s**, immediately when the app opens, and on pull-to-refresh.
- **App in background:** iOS background refresh, roughly every 15 min or less often (iOS decides).
- Only projects in their **build** or **observe** phase are polled.
- Live values update on every poll; a history point is stored at most every 15 min (plus whatever `history` you send), keeping iCloud sync light.

## Minimal implementation (Node/Express)

```js
app.get("/api/prodline", (req, res) => {
  if (req.get("Authorization") !== `Bearer ${process.env.PRODLINE_KEY}`) return res.status(401).end();
  res.json({
    schemaVersion: 1,
    asOf: new Date().toISOString(),
    metrics: [
      { key: "visits", value: totals.visits },
      { key: "social_views", value: totals.socialViews },
      { key: "revenue", value: totals.revenue, unit: "USD" },
    ],
  });
});
```

## Local testing

See [`MockProject/`](../MockProject/README.md) for a dependency-free mock server that implements this contract, including failure modes.
