// Prodline relay: turns GitHub pushes into silent pushes to the phones following that repo, so the
// app refreshes goals, ticks and the streak right away instead of on its next poll.
//
// No accounts. A device registers itself with a random ID and secret; a project gets a hook (random
// ID + secret) that the app generates and the user pastes into the repo's webhook settings. Devices
// that know a hook's secret can follow it (the secret syncs through iCloud Keychain).
//
//   POST   /devices                   {device, secret, token, env}       register or update a device
//   POST   /hooks/:hook               {secret, device, deviceSecret}     follow a hook (creates it)
//   DELETE /hooks/:hook/devices/:dev  {secret, deviceSecret}             stop following
//   POST   /github/:hook              GitHub webhook (X-Hub-Signature-256)
//   POST   /devices/:dev/start-token {deviceSecret, startToken}      Live Activity push-to-start token
//   PUT    /schedules                {device, deviceSecret, items}     deadline activities to start later
//   POST   /waitlist                 {email, website?}                  join the tester waitlist (landing page)
//   GET    /waitlist/metrics         Bearer WAITLIST_KEY (if set)       signups, in the Prodline endpoint format
//   GET    /health
//   cron (every 5 min): starts scheduled Live Activities whose time has come
//
// Storage (KV namespace RELAY):  device:<id> → {secretHash, token, env, startToken?}
//                                sched:<device> → {items: [{id, at, attributes, state, alert, sent?}]}
//                                hook:<id>   → {secret, devices: [ids]}
//                                wait:<sha256(email)> → {email, at};  waitcount → number
// Secrets (wrangler secret put): APNS_KEY (.p8 contents), APNS_KEY_ID, APNS_TEAM_ID; var APNS_TOPIC.
// A key made for the sandbox only won't work for TestFlight / App Store builds: add a production key as
// APNS_KEY_PROD + APNS_KEY_ID_PROD (or use one "Sandbox & Production" key as APNS_KEY for both).

const ID = /^[A-Za-z0-9_-]{16,64}$/;
const MAX_DEVICES_PER_HOOK = 20;

export default {
  fetch: (request, env) => route(request, env),
  scheduled: (_event, env, ctx) => ctx.waitUntil(runSchedules(env)),
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/// Every request: errors become JSON answers with their status. `apns` is swappable for tests.
export async function route(request, env, apns = sendSilentPush) {
  let res;
  try {
    res = await handle(request, env, apns);
  } catch (e) {
    res = e instanceof HttpError ? json({ error: e.message }, e.status) : json({ error: "internal" }, 500);
  }
  // The landing page calls the waitlist from another origin, errors included.
  if (new URL(request.url).pathname.startsWith("/waitlist")) for (const [k, v] of Object.entries(CORS)) res.headers.set(k, v);
  return res;
}

async function handle(request, env, apns) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;

  if (method === "GET" && url.pathname === "/health") return json({ ok: true });

  if (parts[0] === "waitlist") return waitlist(request, env, parts, method);

  if (method === "POST" && parts.length === 1 && parts[0] === "devices") {
    const body = await readJSON(request);
    requireId(body.device, "device");
    requireString(body.secret, "secret", 16);
    if (!/^[0-9a-fA-F]{32,200}$/.test(body.token ?? "")) throw new HttpError(400, "bad token");
    const envName = body.env === "sandbox" ? "sandbox" : "production";
    const key = `device:${body.device}`;
    const existing = await getJSON(env, key);
    const hash = await sha256(body.secret);
    if (existing && !timingSafeEqual(existing.secretHash, hash)) throw new HttpError(403, "wrong device secret");
    // Keep the push-to-start token across re-registrations.
    await env.RELAY.put(key, JSON.stringify({ ...(existing ?? {}), secretHash: hash, token: body.token.toLowerCase(), env: envName }));
    return json({ ok: true });
  }

  if (method === "POST" && parts.length === 3 && parts[0] === "devices" && parts[2] === "start-token") {
    const id = parts[1];
    requireId(id, "device");
    const body = await readJSON(request);
    const device = await requireDevice(env, id, body.deviceSecret);
    if (!/^[0-9a-fA-F]{32,300}$/.test(body.startToken ?? "")) throw new HttpError(400, "bad token");
    await env.RELAY.put(`device:${id}`, JSON.stringify({ ...device, startToken: body.startToken.toLowerCase() }));
    return json({ ok: true });
  }

  if (method === "PUT" && parts.length === 1 && parts[0] === "schedules") {
    const body = await readJSON(request);
    requireId(body.device, "device");
    await requireDevice(env, body.device, body.deviceSecret);
    const items = Array.isArray(body.items) ? body.items : [];
    if (items.length > 10) throw new HttpError(400, "too many items");
    for (const it of items) {
      if (typeof it?.id !== "string" || it.id.length > 64 || typeof it.at !== "number"
          || typeof it.attributes !== "object" || typeof it.state !== "object") throw new HttpError(400, "bad item");
    }
    if (JSON.stringify(items).length > 16000) throw new HttpError(413, "too large");
    const key = `sched:${body.device}`;
    // Keep "already sent" marks for items that are still listed, so an upload can't start one twice.
    const old = (await getJSON(env, key))?.items ?? [];
    const sent = new Set(old.filter((i) => i.sent).map((i) => `${i.id}@${i.at}`));
    const next = items.map((i) => ({ ...i, sent: sent.has(`${i.id}@${i.at}`) || undefined }));
    if (next.length) await env.RELAY.put(key, JSON.stringify({ items: next }));
    else await env.RELAY.delete(key);
    return json({ ok: true, items: next.length });
  }

  if (parts[0] === "hooks" && parts.length >= 2) {
    const hookId = parts[1];
    requireId(hookId, "hook");
    const body = await readJSON(request);
    requireString(body.secret, "secret", 16);
    const key = `hook:${hookId}`;
    const hook = await getJSON(env, key);
    if (hook && !timingSafeEqual(hook.secret, body.secret)) throw new HttpError(403, "wrong hook secret");

    if (method === "POST" && parts.length === 2) {
      requireId(body.device, "device");
      await requireDevice(env, body.device, body.deviceSecret);
      const devices = new Set(hook?.devices ?? []);
      devices.add(body.device);
      if (devices.size > MAX_DEVICES_PER_HOOK) throw new HttpError(429, "too many devices");
      if (!hook || devices.size !== hook.devices.length) {
        await env.RELAY.put(key, JSON.stringify({ secret: body.secret, devices: [...devices] }));
      }
      return json({ ok: true, devices: devices.size });
    }

    if (method === "DELETE" && parts.length === 4 && parts[2] === "devices") {
      const device = parts[3];
      requireId(device, "device");
      await requireDevice(env, device, body.deviceSecret);
      if (!hook) return json({ ok: true });
      const devices = hook.devices.filter((d) => d !== device);
      if (devices.length) await env.RELAY.put(key, JSON.stringify({ ...hook, devices }));
      else await env.RELAY.delete(key);
      return json({ ok: true });
    }
  }

  if (method === "POST" && parts.length === 2 && parts[0] === "github") {
    const hookId = parts[1];
    requireId(hookId, "hook");
    const raw = await request.text();
    const hook = await getJSON(env, `hook:${hookId}`);
    // Unknown hooks and bad signatures look the same from outside.
    const signature = request.headers.get("x-hub-signature-256") ?? "";
    if (!hook || !(await validSignature(hook.secret, raw, signature))) throw new HttpError(401, "bad signature");

    const event = request.headers.get("x-github-event") ?? "";
    if (event === "ping") return json({ ok: true, pong: true });
    if (!["push", "issues", "pull_request", "release"].includes(event)) return json({ ok: true, ignored: event });

    let payload = {};
    try { payload = JSON.parse(raw); } catch { throw new HttpError(400, "bad json"); }
    const message = {
      aps: { "content-available": 1 },
      prodline: { hook: hookId, event, repo: payload.repository?.full_name ?? "", commits: payload.commits?.length ?? 0 },
    };

    let sent = 0;
    const gone = [];
    // Apple's answers, so a webhook delivery in GitHub shows why a push didn't go out (403 = key problem).
    const apple = [];
    for (const id of hook.devices) {
      const device = await getJSON(env, `device:${id}`);
      if (!device) { gone.push(id); continue; }
      const status = await apns(env, device, message);
      apple.push(status);
      if (status === 200) sent++;
      // 410: the app was deleted or the token changed for good.
      if (status === 410 || status === 400) gone.push(id);
    }
    if (gone.length) {
      const devices = hook.devices.filter((d) => !gone.includes(d));
      await env.RELAY.put(`hook:${hookId}`, JSON.stringify({ ...hook, devices }));
    }
    return json({ ok: true, sent, apple });
  }

  throw new HttpError(404, "not found");
}

// MARK: - Waitlist (landing page)

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const CORS = { "access-control-allow-origin": "*", "access-control-allow-methods": "POST, GET, OPTIONS",
  "access-control-allow-headers": "content-type, authorization", "access-control-max-age": "86400" };

async function waitlist(request, env, parts, method) {
  if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (method === "POST" && parts.length === 1) {
    const body = await readJSON(request);
    // Bots fill the hidden field; tell them it worked and keep nothing.
    if (body.website) return (json({ ok: true }));
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!EMAIL.test(email)) throw new HttpError(400, "bad email");
    const key = `wait:${await sha256(email)}`;
    if (await env.RELAY.get(key)) return (json({ ok: true, already: true }));
    await env.RELAY.put(key, JSON.stringify({ email, at: new Date().toISOString() }));
    const count = Number(await env.RELAY.get("waitcount") ?? 0) + 1;
    await env.RELAY.put("waitcount", String(count));
    return (json({ ok: true, count }));
  }

  if (method === "GET" && parts.length === 2 && parts[1] === "metrics") {
    if (env.WAITLIST_KEY) {
      const auth = request.headers.get("authorization") ?? "";
      if (!timingSafeEqual(auth, `Bearer ${env.WAITLIST_KEY}`)) throw new HttpError(401, "unauthorized");
    }
    const count = Number(await env.RELAY.get("waitcount") ?? 0);
    return (json({ schemaVersion: 1, project: "Prodline", asOf: new Date().toISOString(),
      metrics: [{ key: "signups", value: count }] }));
  }
  throw new HttpError(404, "not found");
}

// MARK: - Checks

async function requireDevice(env, id, secret) {
  requireString(secret, "deviceSecret", 16);
  const device = await getJSON(env, `device:${id}`);
  if (!device) throw new HttpError(404, "unknown device");
  if (!timingSafeEqual(device.secretHash, await sha256(secret))) throw new HttpError(403, "wrong device secret");
  return device;
}

// MARK: - Scheduled Live Activities

/// Every few minutes: start the deadline Live Activities whose time has come, with a push-to-start.
export async function runSchedules(env, now = Date.now(), send = sendLiveActivityStart) {
  let cursor;
  let started = 0;
  do {
    const page = await env.RELAY.list({ prefix: "sched:", cursor });
    for (const { name } of page.keys) {
      const sched = await getJSON(env, name);
      if (!sched) continue;
      const deviceID = name.slice("sched:".length);
      const device = await getJSON(env, `device:${deviceID}`);
      let changed = false;
      // Forget items whose window is long over.
      const items = sched.items.filter((i) => now / 1000 < i.at + 6 * 3600);
      if (items.length !== sched.items.length) changed = true;
      for (const item of items) {
        if (item.sent || item.at > now / 1000 || !device?.startToken) continue;
        const status = await send(env, device, item, now);
        item.sent = true;
        changed = true;
        if (status === 200) started++;
      }
      if (!changed) continue;
      if (items.length) await env.RELAY.put(name, JSON.stringify({ items }));
      else await env.RELAY.delete(name);
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return started;
}

/// The APNs payload that starts a Live Activity on a device that isn't running the app.
export function liveActivityStartPayload(item, now = Date.now()) {
  const aps = {
    timestamp: Math.floor(now / 1000),
    event: "start",
    "attributes-type": "DeadlineAttributes",
    attributes: item.attributes,
    "content-state": item.state,
    alert: item.alert ?? { title: "Deadline tonight", body: "Four hours left." },
  };
  if (typeof item.staleAt === "number") aps["stale-date"] = Math.floor(item.staleAt);
  return { aps };
}

export async function sendLiveActivityStart(env, device, item, now = Date.now()) {
  const production = device.env !== "sandbox";
  const host = production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${device.startToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken(env, now, production)}`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-topic": `${env.APNS_TOPIC}.push-type.liveactivity`,
    },
    body: JSON.stringify(liveActivityStartPayload(item, now)),
  });
  return res.status;
}

function requireId(v, name) {
  if (typeof v !== "string" || !ID.test(v)) throw new HttpError(400, `bad ${name}`);
}

function requireString(v, name, min) {
  if (typeof v !== "string" || v.length < min || v.length > 200) throw new HttpError(400, `bad ${name}`);
}

async function readJSON(request) {
  try { return (await request.json()) ?? {}; } catch { throw new HttpError(400, "bad json"); }
}

async function getJSON(env, key) {
  const v = await env.RELAY.get(key);
  return v ? JSON.parse(v) : null;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}

// MARK: - Crypto

const enc = new TextEncoder();

function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256(s) {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(s)));
}

export function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// GitHub signs the raw body with HMAC-SHA256: "sha256=<hex>".
export async function validSignature(secret, body, header) {
  if (!header.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = "sha256=" + hex(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  return timingSafeEqual(expected, header);
}

// MARK: - APNs

const cachedTokens = {}; // sandbox / production → {jwt, at}

function b64url(bytes) {
  let s = typeof bytes === "string" ? btoa(bytes) : btoa(String.fromCharCode(...new Uint8Array(bytes)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Provider token for APNs (ES256), reused for 50 minutes as Apple asks.
/// The key for an environment: production uses the *_PROD secrets when they're set.
export function apnsKey(env, production) {
  if (production && env.APNS_KEY_PROD && env.APNS_KEY_ID_PROD) return { pem: env.APNS_KEY_PROD, id: env.APNS_KEY_ID_PROD };
  return { pem: env.APNS_KEY, id: env.APNS_KEY_ID };
}

export async function apnsToken(env, now = Date.now(), production = false) {
  const slot = production ? "production" : "sandbox";
  const cached = cachedTokens[slot];
  if (cached && now - cached.at < 50 * 60 * 1000) return cached.jwt;
  const { pem: raw, id } = apnsKey(env, production);
  const pem = raw.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: id }));
  const claims = b64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  cachedTokens[slot] = { jwt, at: now };
  return jwt;
}

/// A background (silent) push: wakes the app to refresh, shows nothing.
export async function sendSilentPush(env, device, message) {
  const host = device.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken(env, Date.now(), device.env !== "sandbox")}`,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-topic": env.APNS_TOPIC,
    },
    body: JSON.stringify(message),
  });
  return res.status;
}
