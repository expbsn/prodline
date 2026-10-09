// Local stand-in for the deployed relay: the same routes with in-memory storage, and pushes printed
// instead of sent (deliver them to a simulator with `xcrun simctl push`). Usage: node dev-server.js
import { createServer } from "node:http";
import { route } from "./src/index.js";

const store = new Map();
const env = {
  RELAY: { get: async (k) => store.get(k) ?? null, put: async (k, v) => void store.set(k, v), delete: async (k) => void store.delete(k) },
};
const port = Number(process.env.PORT ?? 8789);

createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  // Dev only: show the hook secret so a test webhook can be signed by hand.
  if (req.url.startsWith("/hooks/") && body) console.log(`hook secret: ${JSON.parse(body).secret}`);
  const request = new Request(`http://localhost:${port}${req.url}`, { method: req.method, headers: req.headers, body });
  const response = await route(request, env, async (_env, device, message) => {
    console.log(`push → ${device.token.slice(0, 12)}… ${JSON.stringify(message)}`);
    return 200;
  });
  console.log(`${req.method} ${req.url} → ${response.status}`);
  res.writeHead(response.status, { "content-type": "application/json" });
  res.end(await response.text());
}).listen(port, () => console.log(`relay dev server on http://127.0.0.1:${port}`));
