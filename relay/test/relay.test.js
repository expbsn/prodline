import { test } from "node:test";
import assert from "node:assert/strict";
import { route, validSignature, apnsToken } from "../src/index.js";

/// In-memory stand-in for the KV namespace.
function kv() {
  const m = new Map();
  return { get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v), delete: async (k) => void m.delete(k), m };
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
