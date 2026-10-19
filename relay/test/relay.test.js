import { test } from "node:test";
import assert from "node:assert/strict";
import { route, validSignature, apnsToken, apnsKey, runSchedules, liveActivityStartPayload, waitSource } from "../src/index.js";

/// In-memory stand-in for the KV namespace.
function kv() {
  const m = new Map();
  return {
    get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v), delete: async (k) => void m.delete(k), m,
    list: async ({ prefix }) => ({ keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }),
  };
}

const BASE = "https://relay.test";
const DEVICE = "dev_aaaaaaaaaaaaaaaa";
const DEVICE_SECRET = "device-secret-0123456789";
const HOOK = "hook_bbbbbbbbbbbbbbbb";
const HOOK_SECRET = "hook-secret-0123456789ab";
const TOKEN = "ab".repeat(32);

function req(path, method, body, headers = {}) {
  return new Request(BASE + path, { method, body: typeof body === "string" ? body : JSON.stringify(body), headers });
}

async function sign(secret, body) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return "sha256=" + [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function setup(env) {
  let r = await route(req("/devices", "POST", { device: DEVICE, secret: DEVICE_SECRET, token: TOKEN, env: "sandbox" }), env);
  assert.equal(r.status, 200);
  r = await route(req(`/hooks/${HOOK}`, "POST", { secret: HOOK_SECRET, device: DEVICE, deviceSecret: DEVICE_SECRET }), env);
  assert.equal(r.status, 200);
}

async function deliver(env, event, payload, apns, secret = HOOK_SECRET) {
  const raw = JSON.stringify(payload);
  const headers = { "x-github-event": event, "x-hub-signature-256": await sign(secret, raw) };
  return route(req(`/github/${HOOK}`, "POST", raw, headers), { ...env }, apns);
}

test("a signed push wakes every following device", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  const sent = [];
  const r = await deliver(env, "push", { repository: { full_name: "kian/kite" }, commits: [{}, {}] }, async (_e, d, m) => { sent.push([d, m]); return 200; });
  assert.equal(r.status, 200);
  assert.equal((await r.json()).sent, 1);
  assert.equal(sent[0][0].token, TOKEN);
  assert.equal(sent[0][0].env, "sandbox");
  assert.deepEqual(sent[0][1].prodline, { hook: HOOK, event: "push", repo: "kian/kite", commits: 2 });
  assert.equal(sent[0][1].aps["content-available"], 1);
});

test("a wrong signature is refused and sends nothing", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  let calls = 0;
  const r = await deliver(env, "push", {}, async () => { calls++; return 200; }, "some-other-secret-xyz");
  assert.equal(r.status, 401);
  assert.equal(calls, 0);
});

test("ping answers without pushing", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  const r = await deliver(env, "ping", { zen: "hi" }, async () => { throw new Error("no push expected"); });
  assert.equal((await r.json()).pong, true);
});

test("following a hook needs its secret and the device's own secret", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  let r = await route(req(`/hooks/${HOOK}`, "POST", { secret: "wrong-secret-0123456789", device: DEVICE, deviceSecret: DEVICE_SECRET }), env);
  assert.equal(r.status, 403);
  r = await route(req(`/hooks/${HOOK}`, "POST", { secret: HOOK_SECRET, device: DEVICE, deviceSecret: "wrong-device-secret-01" }), env);
  assert.equal(r.status, 403);
  // Someone else can't take over a registered device.
  r = await route(req("/devices", "POST", { device: DEVICE, secret: "attacker-secret-0123456", token: TOKEN }), env);
  assert.equal(r.status, 403);
});

test("devices Apple says are gone get dropped", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  await deliver(env, "push", {}, async () => 410);
  const hook = JSON.parse(await env.RELAY.get(`hook:${HOOK}`));
  assert.deepEqual(hook.devices, []);
});

test("unfollowing removes the device and finally the hook", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  const r = await route(req(`/hooks/${HOOK}/devices/${DEVICE}`, "DELETE", { secret: HOOK_SECRET, deviceSecret: DEVICE_SECRET }), env);
  assert.equal(r.status, 200);
  assert.equal(await env.RELAY.get(`hook:${HOOK}`), null);
});

test("bad input is rejected", async () => {
  const env = { RELAY: kv() };
  let r = await route(req("/devices", "POST", { device: "x", secret: DEVICE_SECRET, token: TOKEN }), env);
  assert.equal(r.status, 400);
  r = await route(req("/devices", "POST", { device: DEVICE, secret: DEVICE_SECRET, token: "nothex" }), env);
  assert.equal(r.status, 400);
  r = await route(req("/nope", "GET"), env);
  assert.equal(r.status, 404);
});

test("GitHub's documented signature example verifies", async () => {
  // https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
  assert.equal(await validSignature("It's a Secret to Everybody", "Hello, World!",
    "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"), true);
  assert.equal(await validSignature("It's a Secret to Everybody", "Hello, World!", "sha256=00"), false);
});

test("the APNs token is a valid ES256 JWT", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  const pem = `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`;
  const jwt = await apnsToken({ APNS_KEY: pem, APNS_KEY_ID: "KEY123", APNS_TEAM_ID: "TEAM456" }, 1_800_000_000_000);
  const [h, c, s] = jwt.split(".");
  const dec = (x) => JSON.parse(Buffer.from(x, "base64url").toString());
  assert.deepEqual(dec(h), { alg: "ES256", kid: "KEY123" });
  assert.deepEqual(dec(c), { iss: "TEAM456", iat: 1_800_000_000 });
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, Buffer.from(s, "base64url"), new TextEncoder().encode(`${h}.${c}`));
  assert.equal(ok, true);
});

test("production uses its own key when one is set", () => {
  const env = { APNS_KEY: "sandbox-pem", APNS_KEY_ID: "SBX", APNS_KEY_PROD: "prod-pem", APNS_KEY_ID_PROD: "PRD" };
  assert.deepEqual(apnsKey(env, false), { pem: "sandbox-pem", id: "SBX" });
  assert.deepEqual(apnsKey(env, true), { pem: "prod-pem", id: "PRD" });
  // Without production secrets, one key serves both.
  assert.deepEqual(apnsKey({ APNS_KEY: "k", APNS_KEY_ID: "K" }, true), { pem: "k", id: "K" });
});

test("scheduled Live Activities start once, when their time comes", async () => {
  const env = { RELAY: kv() };
  await setup(env);
  let r = await route(req(`/devices/${DEVICE}/start-token`, "POST", { deviceSecret: DEVICE_SECRET, startToken: "cd".repeat(40) }), env);
  assert.equal(r.status, 200);
  const at = 1_800_000_000;
  const item = { id: "m1", at, attributes: { milestoneID: "m1" }, state: { goalCount: 2 }, alert: { title: "t", body: "b" } };
  r = await route(req("/schedules", "PUT", { device: DEVICE, deviceSecret: DEVICE_SECRET, items: [item] }), env);
  assert.equal(r.status, 200);

  const sent = [];
  const send = async (_e, device, it) => { sent.push([device.startToken, it.id]); return 200; };
  assert.equal(await runSchedules(env, (at - 60) * 1000, send), 0);
  assert.equal(await runSchedules(env, (at + 60) * 1000, send), 1);
  assert.equal(await runSchedules(env, (at + 120) * 1000, send), 0);
  assert.deepEqual(sent, [["cd".repeat(40), "m1"]]);

  // Re-uploading the same item keeps it marked as sent.
  await route(req("/schedules", "PUT", { device: DEVICE, deviceSecret: DEVICE_SECRET, items: [item] }), env);
  assert.equal(await runSchedules(env, (at + 180) * 1000, send), 0);
  // Long after the window it's forgotten.
  await runSchedules(env, (at + 7 * 3600) * 1000, send);
  assert.equal(await env.RELAY.get(`sched:${DEVICE}`), null);
});

test("the push-to-start payload carries the activity", () => {
  const p = liveActivityStartPayload({ attributes: { a: 1 }, state: { b: 2 }, alert: { title: "T", body: "B" }, staleAt: 99 }, 5000);
  assert.equal(p.aps.event, "start");
  assert.equal(p.aps["attributes-type"], "DeadlineAttributes");
  assert.deepEqual(p.aps["content-state"], { b: 2 });
  assert.equal(p.aps.timestamp, 5);
  assert.equal(p.aps["stale-date"], 99);
});

test("waitlist: signs up once, ignores bots, reports signups", async () => {
  const env = { RELAY: kv() };
  let r = await route(req("/waitlist", "POST", { email: " Ada@Example.com " }), env);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("access-control-allow-origin"), "*");
  assert.equal((await r.json()).count, 1);
  r = await route(req("/waitlist", "POST", { email: "ada@example.com" }), env);
  assert.equal((await r.json()).already, true);
  r = await route(req("/waitlist", "POST", { email: "bot@spam.com", website: "x" }), env);
  assert.equal(r.status, 200);
  r = await route(req("/waitlist", "POST", { email: "nope" }), env);
  assert.equal(r.status, 400);
  assert.equal(r.headers.get("access-control-allow-origin"), "*");
  r = await route(req("/waitlist", "OPTIONS"), env);
  assert.equal(r.status, 204);
  r = await route(new Request(BASE + "/waitlist/metrics"), env);
  assert.deepEqual((await r.json()).metrics, [{ key: "signups", value: 1 }, { key: "signups_from_direct", value: 1 }]);
  const locked = { ...env, WAITLIST_KEY: "k".repeat(20) };
  r = await route(new Request(BASE + "/waitlist/metrics"), locked);
  assert.equal(r.status, 401);
  r = await route(new Request(BASE + "/waitlist/metrics", { headers: { authorization: "Bearer " + "k".repeat(20) } }), locked);
  assert.equal(r.status, 200);
});

test("waitlist: counts signups per ?ref= source", async () => {
  const env = { RELAY: kv() };
  await route(req("/waitlist", "POST", { email: "a@x.com", source: "SideProject" }), env);
  await route(req("/waitlist", "POST", { email: "b@x.com", source: "sideproject" }), env);
  await route(req("/waitlist", "POST", { email: "c@x.com", source: "indie hackers!" }), env);
  await route(req("/waitlist", "POST", { email: "a@x.com", source: "x" }), env); // already on the list: not counted again
  const r = await route(new Request(BASE + "/waitlist/metrics"), env);
  const m = Object.fromEntries((await r.json()).metrics.map((x) => [x.key, x.value]));
  assert.equal(m.signups, 3);
  assert.equal(m.signups_from_sideproject, 2);
  assert.equal(m.signups_from_indie_hackers, 1);
  assert.equal(m.signups_from_x, undefined);
  assert.equal(waitSource("  "), "direct");
  assert.equal(waitSource("../../etc"), "etc");
});

// MARK: - Social sign-in

const STATE = "st_cccccccccccccccccccc";
const VERIFIER = "verifier-0123456789abcdef0123456789abcdef";
const OAUTH_ENV = () => ({ RELAY: kv(), TIKTOK_CLIENT_KEY: "ck", TIKTOK_CLIENT_SECRET: "cs", INSTAGRAM_APP_ID: "ia", INSTAGRAM_APP_SECRET: "is" });

async function challenge(v) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(v));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function provider(answers) {
  const calls = [];
  const http = async (url, init) => {
    calls.push([String(url), init?.body ? String(init.body) : ""]);
    const hit = answers.find(([match]) => String(url).includes(match));
    return new Response(JSON.stringify(hit?.[1] ?? {}), { status: hit?.[2] ?? 200 });
  };
  return { http, calls };
}

test("TikTok sign-in: start, callback, one handoff", async () => {
  const env = OAUTH_ENV();
  const { http, calls } = provider([["open.tiktokapis.com", { access_token: "at", refresh_token: "rt", expires_in: 86400, refresh_expires_in: 31536000, open_id: "u1" }]]);
  let r = await route(req(`/oauth/tiktok/start?state=${STATE}&challenge=${await challenge(VERIFIER)}`, "GET"), env, undefined, http);
  assert.equal(r.status, 302);
  const auth = new URL(r.headers.get("location"));
  assert.equal(auth.host, "www.tiktok.com");
  assert.equal(auth.searchParams.get("client_key"), "ck");
  assert.equal(auth.searchParams.get("redirect_uri"), `${BASE}/oauth/tiktok/callback`);

  r = await route(req(`/oauth/tiktok/callback?code=abc&state=${STATE}`, "GET"), env, undefined, http);
  assert.equal(r.headers.get("location"), `prodline://oauth/tiktok?state=${STATE}`);
  assert.match(calls[0][1], /client_secret=cs/);
  assert.match(calls[0][1], /code=abc/);

  r = await route(req("/oauth/handoff", "POST", { state: STATE, verifier: "wrong-verifier-0123456789abcdef0123" }), env, undefined, http);
  assert.equal(r.status, 404);
  r = await route(req("/oauth/handoff", "POST", { state: STATE, verifier: VERIFIER }), env, undefined, http);
  const t = await r.json();
  assert.equal(t.access, "at");
  assert.equal(t.refresh, "rt");
  assert.equal(t.user, "u1");
  r = await route(req("/oauth/handoff", "POST", { state: STATE, verifier: VERIFIER }), env, undefined, http);
  assert.equal(r.status, 404);
});

test("Instagram sign-in swaps for a long-lived token", async () => {
  const env = OAUTH_ENV();
  const { http, calls } = provider([
    ["api.instagram.com", { data: [{ access_token: "short", user_id: 42 }] }],
    ["graph.instagram.com", { access_token: "long", expires_in: 5184000 }],
  ]);
  await route(req(`/oauth/instagram/start?state=${STATE}&challenge=${await challenge(VERIFIER)}`, "GET"), env, undefined, http);
  const r = await route(req(`/oauth/instagram/callback?code=abc%23_&state=${STATE}`, "GET"), env, undefined, http);
  assert.equal(r.headers.get("location"), `prodline://oauth/instagram?state=${STATE}`);
  assert.match(calls[0][1], /code=abc(&|$)/);
  assert.match(calls[1][0], /ig_exchange_token/);
  const t = await (await route(req("/oauth/handoff", "POST", { state: STATE, verifier: VERIFIER }), env, undefined, http)).json();
  assert.equal(t.access, "long");
  assert.equal(t.user, "42");
});

test("sign-in errors go back to the app, missing setup is 503", async () => {
  const env = OAUTH_ENV();
  const { http } = provider([["open.tiktokapis.com", { error: "invalid_grant" }, 400]]);
  await route(req(`/oauth/tiktok/start?state=${STATE}&challenge=${await challenge(VERIFIER)}`, "GET"), env, undefined, http);
  let r = await route(req(`/oauth/tiktok/callback?error=access_denied&state=${STATE}`, "GET"), env, undefined, http);
  assert.equal(r.headers.get("location"), `prodline://oauth/tiktok?state=${STATE}&error=denied`);
  r = await route(req(`/oauth/tiktok/callback?code=x&state=${STATE}`, "GET"), env, undefined, http);
  assert.equal(r.headers.get("location"), `prodline://oauth/tiktok?state=${STATE}&error=failed`);
  r = await route(req(`/oauth/threads/start?state=${STATE}&challenge=${await challenge(VERIFIER)}`, "GET"), env, undefined, http);
  assert.equal(r.status, 503);
  assert.equal((await route(new Request(`${BASE}/oauth/threads/start`, { method: "HEAD" }), env, undefined, http)).status, 503);
  assert.equal((await route(new Request(`${BASE}/oauth/tiktok/start`, { method: "HEAD" }), env, undefined, http)).status, 204);
});

test("TikTok refresh uses the client secret", async () => {
  const env = OAUTH_ENV();
  const { http, calls } = provider([["open.tiktokapis.com", { access_token: "at2", refresh_token: "rt2", expires_in: 86400, refresh_expires_in: 100, open_id: "u1" }]]);
  const r = await route(req("/oauth/tiktok/refresh", "POST", { refresh_token: "rt-old-123" }), env, undefined, http);
  assert.equal((await r.json()).access, "at2");
  assert.match(calls[0][1], /grant_type=refresh_token/);
  assert.match(calls[0][1], /client_secret=cs/);
});
