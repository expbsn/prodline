# Prodline relay

Turns GitHub pushes into silent pushes, so the app syncs a repo within seconds, even while it's closed.
It also starts the deadline Live Activity at 20:00 with a push-to-start: the app uploads its upcoming
deadline windows, and a cron trigger (every 5 minutes) starts each one when it opens.
A Cloudflare Worker with KV storage; everything fits Cloudflare's free plan (100k requests/day,
1k KV writes/day; writes only happen when a device or repo registers).

```
GitHub ── webhook (signed) ──▶ relay ── silent push (APNs) ──▶ iPhone ── syncs that repo
```

No accounts: a device registers with a random ID and a secret that stays on it; each project gets a hook
(ID + secret) that the app generates and the user adds as a webhook to the repo. See `src/index.js` for
the routes.

## Test

```bash
npm test                  # unit tests, no dependencies
node dev-server.js        # local relay on :8789 that prints pushes instead of sending them
```

Point the simulator at it: Me → Configuration → Relay → `http://127.0.0.1:8789`. In DEBUG builds,
`-PRODLINE_RELAY_TOKEN <hex>` fakes an APNs token, since simulators often don't get one.

## Deploy (once)

1. Cloudflare: `npx wrangler login`, then `npx wrangler kv namespace create RELAY` and paste the id into
   `wrangler.toml`.
2. Apple: developer.apple.com → Certificates, IDs & Profiles → Keys → + → enable Apple Push Notifications
   service (APNs). Download the .p8 (only once) and note the Key ID and your Team ID.
3. Secrets (never in the repo):
   ```bash
   npx wrangler secret put APNS_KEY       # paste the whole .p8 file
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID
   ```
4. `npm run deploy`. It prints `https://prodline-relay.<you>.workers.dev`; check `/health`.
5. In the app: Me → Configuration → Relay → that address. Then each project's Connection screen shows the
   webhook to add to its repo.

Debug builds register as `sandbox`, TestFlight and App Store builds as `production`; the relay sends to
the matching APNs host. Apple's key environment matters: a key created for **Sandbox** only can't push to
TestFlight or App Store builds. Before the first TestFlight build, either create one key for
**Sandbox & Production** and replace `APNS_KEY` / `APNS_KEY_ID`, or add a production key next to the
sandbox one:

```bash
npx wrangler secret put APNS_KEY_PROD
npx wrangler secret put APNS_KEY_ID_PROD
```
