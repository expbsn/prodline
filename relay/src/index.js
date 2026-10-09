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
//   GET    /health
//
// Storage (KV namespace RELAY):  device:<id> → {secretHash, token, env}
//                                hook:<id>   → {secret, devices: [ids]}
// Secrets (wrangler secret put): APNS_KEY (.p8 contents), APNS_KEY_ID, APNS_TEAM_ID; var APNS_TOPIC.

const ID = /^[A-Za-z0-9_-]{16,64}$/;
const MAX_DEVICES_PER_HOOK = 20;

export default {
  fetch: (request, env) => route(request, env),
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/// Every request: errors become JSON answers with their status. `apns` is swappable for tests.
export async function route(request, env, apns = sendSilentPush) {
  try {
    return await handle(request, env, apns);
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    return json({ error: "internal" }, 500);
  }
}

async function handle(request, env, apns) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;

  if (method === "GET" && url.pathname === "/health") return json({ ok: true });

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
    await env.RELAY.put(key, JSON.stringify({ secretHash: hash, token: body.token.toLowerCase(), env: envName }));
    return json({ ok: true });
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
    for (const id of hook.devices) {
      const device = await getJSON(env, `device:${id}`);
      if (!device) { gone.push(id); continue; }
      const status = await apns(env, device, message);
      if (status === 200) sent++;
      // 410: the app was deleted or the token changed for good.
      if (status === 410 || status === 400) gone.push(id);
    }
    if (gone.length) {
      const devices = hook.devices.filter((d) => !gone.includes(d));
      await env.RELAY.put(`hook:${hookId}`, JSON.stringify({ ...hook, devices }));
    }
    return json({ ok: true, sent });
  }

  throw new HttpError(404, "not found");
}

// MARK: - Checks

async function requireDevice(env, id, secret) {
  requireString(secret, "deviceSecret", 16);
  const device = await getJSON(env, `device:${id}`);
  if (!device) throw new HttpError(404, "unknown device");
  if (!timingSafeEqual(device.secretHash, await sha256(secret))) throw new HttpError(403, "wrong device secret");
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

let cachedToken = null; // {jwt, at}

function b64url(bytes) {
  let s = typeof bytes === "string" ? btoa(bytes) : btoa(String.fromCharCode(...new Uint8Array(bytes)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Provider token for APNs (ES256), reused for 50 minutes as Apple asks.
export async function apnsToken(env, now = Date.now()) {
  if (cachedToken && now - cachedToken.at < 50 * 60 * 1000) return cachedToken.jwt;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  cachedToken = { jwt, at: now };
  return jwt;
}

/// A background (silent) push: wakes the app to refresh, shows nothing.
export async function sendSilentPush(env, device, message) {
  const host = device.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken(env)}`,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-topic": env.APNS_TOPIC,
    },
    body: JSON.stringify(message),
  });
  return res.status;
}
