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
