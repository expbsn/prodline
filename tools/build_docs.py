#!/usr/bin/env python3
"""Builds web/docs.html, the setup guide on the website.

The integration part is read straight from prodline/Services/Integrations.swift (what each service
provides, the fields and key it needs, and the in-app setup steps), so the website never drifts from
the app. GitHub, instant updates and the custom endpoint follow docs/API.md and the in-app guides.

    python3 tools/build_docs.py
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = (ROOT / "prodline/Services/Integrations.swift").read_text()
OUT = ROOT / "web/docs.html"
SUPPORT = "info@prodline.build"

STR = r'"((?:[^"\\]|\\.)*)"'


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def block(var):
    """The body of `var <name>: ... { switch self { ... } }`."""
    start = SWIFT.index(f"var {var}:")
    i = SWIFT.index("switch self {", start) + len("switch self {")
    depth = 1
    j = i
    while depth:
        c = SWIFT[j]
        depth += c == "{"
        depth -= c == "}"
        j += 1
    return SWIFT[i:j - 1]


def cases(body):
    """case .a, .b: <rest> → {a: rest, b: rest}; rest runs until the next top-level case."""
    out = {}
    parts = re.split(r"\n\s*case ", "\n" + body)
    for part in parts[1:]:
        names, _, rest = part.partition(":")
        for n in names.split(","):
            n = n.strip().lstrip(".")
            if n:
                out[n] = rest
    return out


titles = {k: unescape(re.search(STR, v).group(1)) for k, v in cases(block("title")).items()}
provides = {k: unescape(re.search(STR, v).group(1)) for k, v in cases(block("provides")).items()}
secret = {k: (unescape(m.group(1)) if (m := re.search(STR, v)) else "") for k, v in cases(block("secretLabel")).items()}
steps = {k: [unescape(s) for s in re.findall(STR, v)] for k, v in cases(block("steps")).items()}
fields = {}
for k, v in cases(block("fields")).items():
    fs = []
    for m in re.finditer(r"Field\(key: " + STR + r", label: " + STR + r", placeholder: " + STR + r"(, optional: true)?", v):
        fs.append((unescape(m.group(2)), bool(m.group(4))))
    fields[k] = fs

# Built but not offered yet (IntegrationKind.isAvailable).
HIDDEN = {"threads"}
kinds = [k for k in titles if k not in HIDDEN]
GROUPS = [
    ("revenue", "Revenue and stores", ["appStore", "revenueCat", "stripe", "lemonSqueezy", "gumroad", "shopify", "paddle", "polar"]),
    ("analytics", "Analytics", ["plausible", "umami", "fathom", "posthog", "simpleAnalytics"]),
    ("hosting", "Hosting", ["vercel", "netlify"]),
    ("newsletters", "Newsletters", ["kit", "buttondown", "beehiiv"]),
    ("community", "Launches, packages and social", ["youtube", "tiktok", "instagram", "productHunt", "hackerNews", "npm", "bluesky"]),
]
assert sorted(k for _, _, ks in GROUPS for k in ks) == sorted(kinds), "every integration needs a group"


def slug(k):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", k).lower()


def code_inline(text):
    # `x` → <code>x</code>, the rest escaped
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text))


def integration(k):
    keyless = not secret[k]
    need = []
    signin = secret[k] == "Sign-in"
    if signin:
        need.append(f"<li><b>Your {html.escape(titles[k])} login</b> <span>read-only, kept in your Keychain</span></li>")
    elif secret[k]:
        need.append(f"<li><b>{html.escape(secret[k])}</b> <span>kept in your Keychain</span></li>")
    for label, optional in fields[k]:
        need.append(f"<li>{html.escape(label)}{' <span>optional</span>' if optional else ''}</li>")
    if keyless and not fields[k]:
        need.append("<li>Nothing</li>")
    lis = "".join(f"<li>{code_inline(s)}</li>" for s in steps[k])
    badge = '<span class="tag">No key</span>' if keyless else '<span class="tag">Sign in</span>' if signin else ""
    return f'''        <article class="intg-doc" id="{slug(k)}">
          <header><h4>{html.escape(titles[k])}</h4>{badge}</header>
          <p class="provides">{html.escape(provides[k])}</p>
          <div class="intg-cols">
            <div><p class="label">You'll need</p><ul class="need">{"".join(need)}</ul></div>
            <div><p class="label">Set up</p><ol class="steps">{lis}</ol></div>
          </div>
        </article>
'''


toc_groups = "".join(
    f'<li><a href="#{gid}">{html.escape(name)}</a></li>' for gid, name, _ in GROUPS)
groups = "".join(
    f'      <section class="doc-group" id="{gid}">\n        <h3>{html.escape(name)}</h3>\n'
    + "".join(integration(k) for k in ks) + "      </section>\n"
    for gid, name, ks in GROUPS)

PAGE = f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Docs · Prodline</title>
  <meta name="description" content="Set up Prodline: every integration, GitHub, instant updates and your own endpoint, step by step.">
  <meta name="theme-color" content="#07080B">
  <meta name="color-scheme" content="dark">
  <link rel="icon" href="mark.svg" type="image/svg+xml">
  <link rel="preload" href="fonts/AfacadFlux.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="style.css?v=47">
</head>
<!-- Generated by tools/build_docs.py from the app's source. Edit the script, not this file. -->
<body class="doc-page">
  <header class="nav" id="top">
    <a class="logo" href="index.html" aria-label="Prodline home"><img src="mark-light.svg" alt="" width="26" height="26"><span>Prodline</span></a>
    <nav class="links" aria-label="Main">
      <a href="index.html#how">How it works</a>
      <a href="index.html#integrations">Integrations</a>
      <a href="index.html#features">Features</a>
      <a href="docs.html" class="on solid">Docs</a>
      <a href="faq.html">FAQ</a>
    </nav>
    <a class="btn light small" href="index.html#join">Join the beta</a>
  </header>

  <div class="docs">
    <aside class="docs-toc" aria-label="On this page">
      <p class="label">On this page</p>
      <ol>
        <li><a href="#overview">Three ways in</a></li>
        <li><a href="#integrations">Integrations</a><ol>{toc_groups}</ol></li>
        <li><a href="#github">GitHub</a><ol><li><a href="#prodline-json">prodline.json</a></li><li><a href="#issues">Issues and milestones</a></li><li><a href="#instant">Instant updates</a></li></ol></li>
        <li><a href="#endpoint">Your own endpoint</a><ol><li><a href="#endpoint-response">Response</a></li><li><a href="#endpoint-goals">Goals</a></li><li><a href="#endpoint-github">GitHub as the endpoint</a></li><li><a href="#endpoint-polling">Polling and errors</a></li></ol></li>
        <li><a href="#seamless">A seamless setup</a></li>
      </ol>
    </aside>

    <main class="doc docs-main">
      <p class="eyebrow">Docs</p>
      <h1>Connect everything once.</h1>
      <p class="lede">Prodline brings numbers and goals into your projects on its own. Here is every way in, and how to set each one up so you never refresh a dashboard again.</p>

      <section id="overview">
        <h2>Three ways in</h2>
        <div class="ways">
          <a class="way" href="#integrations"><b>Integrations</b><span>25 services for revenue, visits, downloads, deploys, views, subscribers and followers. Paste a key or sign in, done.</span></a>
          <a class="way" href="#github"><b>GitHub</b><span>Your plan from <code>prodline.json</code>, goals from issues, commits for your streak. Instant with a webhook.</span></a>
          <a class="way" href="#endpoint"><b>Your own endpoint</b><span>Anything else: return a small JSON file and Prodline polls it.</span></a>
        </div>
        <p>Everything lives on the project: open it and tap <b>Connection</b>. You can combine all three on one project; numbers from every source add up, and revenue that two sources both count (RevenueCat and App Store Connect) is only counted once.</p>
      </section>

      <section id="integrations">
        <h2>Integrations</h2>
        <p>Open the project → <b>Connection</b> → <b>Integrations</b> and pick a service. Keys are stored in the iOS Keychain on your iPhone and sent only to the service they belong to. Numbers count from the day the project started, so older sales or views don't inflate them.</p>
{groups}      </section>

      <section id="github">
        <h2>GitHub</h2>
        <p>Open the project → <b>Connection</b> → <b>GitHub</b> and enter the repository as <code>owner/repo</code>. A token is optional: add one for private repositories and a higher rate limit (it stays in the Keychain). Prodline reads the repo every 10 minutes, counts commits toward Momentum and your streak, and turns the README and open issues into goal suggestions.</p>

        <h3 id="prodline-json">prodline.json: your plan in the repo</h3>
        <p>Add <code>prodline.json</code> at the root of the repository and it becomes the project's plan: exactly its checkpoints and goals, nothing else. Mark a goal done in a commit and it ticks itself in the app.</p>
<pre><code>{{
  "version": 1,
  "checkpoints": [
    {{ "day": 4,  "title": "Core loop" }},
    {{ "day": 10, "title": "Onboarding" }}
  ],
  "goals": [
    {{ "id": "streak-card", "title": "Shareable streak card", "day": 4, "done": true }},
    {{ "id": "paywall",     "title": "Paywall screen",        "day": 10 }},
    {{ "id": "signups-50",  "title": "Reach 50 signups",      "day": 10, "metric": {{ "key": "signups", "target": 50 }} }}
  ]
}}</code></pre>
        <ul class="plain">
          <li><code>day</code> counts from the project's start (day 1 = start date), so the plan follows schedule changes. A goal lands on the first checkpoint on or after its day. <code>"due": "YYYY-MM-DD"</code> works for fixed dates.</li>
          <li>Without <code>checkpoints</code>, the goals' days become the checkpoints.</li>
          <li><code>metric</code> goals tick themselves when the number reaches the target.</li>
          <li>Keep <code>id</code>s stable; a missing file clears its open goals, an invalid one is reported and existing goals are kept.</li>
          <li>Building with Claude Code? The GitHub guide in the app has a prompt to copy into <code>CLAUDE.md</code>, so it keeps the plan current and ticks goals as it ships.</li>
        </ul>

        <h3 id="issues">Issues and milestones</h3>
        <p>Without <code>prodline.json</code>, issues in a GitHub milestone or labeled <code>prodline</code> become goals and tick off when closed. A milestone's due date picks the checkpoint; without one, the Nth milestone maps to the Nth checkpoint. Pull requests are ignored.</p>

        <h3 id="instant">Instant updates</h3>
        <p>By default the app checks the repo every few minutes. With a webhook, a push reaches your iPhone within seconds, even when the app is closed.</p>
        <ol class="steps">
          <li>In the app: project → <b>Connection</b> → <b>Instant updates</b>. It shows a payload URL and a secret, each with a copy button.</li>
          <li>On GitHub open the repo → Settings → Webhooks → Add webhook. You need admin access to the repo.</li>
          <li>Paste the payload URL and the secret. Content type: <code>application/json</code>.</li>
          <li>Leave “Just the push event” selected and click Add webhook. GitHub sends a test ping right away.</li>
        </ol>
        <p>The relay only passes the webhook ID, repository name, event type and number of commits on to your device. Turn it off under Me → Configuration by typing <code>off</code> as the relay address. Details in the <a href="privacy.html">privacy policy</a>.</p>
      </section>

      <section id="endpoint">
        <h2>Your own endpoint</h2>
        <p>For anything without an integration, point the project at one HTTPS address: project → <b>Connection</b> → <b>Your own endpoint</b>. Prodline sends</p>
<pre><code>GET &lt;endpoint&gt;?since=&lt;ISO-8601&gt;
Authorization: Bearer &lt;api key&gt;     (left out when you set no key)
Accept: application/json</code></pre>
        <p><code>since</code> is the newest point Prodline already has; return only history after it. The key is yours to create and stays in the Keychain.</p>

        <h3 id="endpoint-response">Response</h3>
<pre><code>{{
  "schemaVersion": 1,
  "asOf": "2026-10-04T12:00:00Z",
  "metrics": [
    {{ "key": "visits",       "value": 8849 }},
    {{ "key": "social_views", "value": 21114 }},
    {{ "key": "revenue",      "value": 529.89, "unit": "USD" }},
    {{ "key": "signups",      "value": 398 }}
  ],
  "history": [
    {{ "asOf": "2026-10-04T11:00:00Z", "metrics": [ {{ "key": "visits", "value": 8790 }} ] }}
  ]
}}</code></pre>
        <ul class="plain">
          <li>Values are <b>running totals</b> (all-time), not deltas. <code>visits</code>, <code>social_views</code> and <code>revenue</code> are built in; any other key shows up as its own number.</li>
          <li><code>history</code> is optional, ideally hourly. Re-sending points is harmless.</li>
        </ul>
<pre><code>// Node / Express
app.get("/api/prodline", (req, res) => {{
  if (req.get("Authorization") !== `Bearer ${{process.env.PRODLINE_KEY}}`) return res.status(401).end();
  res.json({{
    schemaVersion: 1,
    asOf: new Date().toISOString(),
    metrics: [
      {{ key: "visits", value: totals.visits }},
      {{ key: "revenue", value: totals.revenue, unit: "USD" }},
    ],
  }});
}});</code></pre>

        <h3 id="endpoint-goals">Goals</h3>
        <p>Add a <code>goals</code> array to the same response. When present it is the full list.</p>
<pre><code>"goals": [
  {{ "id": "onboarding",  "title": "Onboarding flow live", "checkpoint": 3, "done": false }},
  {{ "id": "launch-post", "title": "Launch post published", "due": "2026-10-08T00:00:00Z" }},
  {{ "id": "signups-500", "title": "500 signups", "checkpoint": 4, "metric": {{ "key": "signups", "target": 500 }} }}
]</code></pre>
        <p><code>checkpoint</code> is the 1-based position in the project's deadlines; <code>due</code> places a goal on the first deadline on or after a date. A checkpoint whose goals are all done completes by itself, with XP and streak as if you tapped it.</p>

        <h3 id="endpoint-github">GitHub as the endpoint</h3>
        <p>No server? A GitHub Action can publish the file for you. In the app, the endpoint page's “Use GitHub as the endpoint” guide has the workflow to copy into <code>.github/workflows/</code>. On every push and every 6 hours it writes <code>metrics.json</code> to a <code>metrics</code> branch; use <code>https://raw.githubusercontent.com/&lt;owner&gt;/&lt;repo&gt;/metrics/metrics.json</code> as the endpoint, with no key. Works for public repositories.</p>

        <h3 id="endpoint-polling">Polling and errors</h3>
        <ul class="plain">
          <li>Every 30 seconds while the app is open (Me → Configuration → Live refresh), and in the background when iOS allows, roughly every 15 minutes.</li>
          <li>Only projects in their build or observe phase are polled.</li>
          <li><code>401</code>/<code>403</code> show “API key rejected”, <code>404</code> “Endpoint not found”; <code>429</code> honors <code>Retry-After</code>; server errors and timeouts back off from 30 seconds up to 15 minutes.</li>
        </ul>
      </section>

      <section id="seamless">
        <h2>A seamless setup</h2>
        <ol class="steps">
          <li><b>Start with money.</b> Connect where revenue lands first (Stripe, RevenueCat, App Store Connect…): it's the number that decides keep or let go.</li>
          <li><b>Add one traffic source.</b> Plausible, Fathom, PostHog, Simple Analytics or Umami for visits; YouTube, TikTok, Instagram or Bluesky if that's where your audience is.</li>
          <li><b>Link the repo and add <code>prodline.json</code>.</b> Your plan lives next to your code, and commits keep the streak alive without opening the app.</li>
          <li><b>Turn on instant updates.</b> One webhook, and goals tick seconds after you push.</li>
          <li><b>Add the widgets.</b> Long-press the Home Screen → Edit → Add Widget → Prodline. The deadline Live Activity appears on its own in the last four hours before a checkpoint.</li>
          <li><b>Pick your three numbers.</b> With more than three, long-press a number on the project or the Data tab to swap it.</li>
        </ol>
        <section class="contact-card">
          <h2>Stuck on a step?</h2>
          <p>Write to <a href="mailto:{SUPPORT}">{SUPPORT}</a> or check the <a href="faq.html">FAQ</a>.</p>
        </section>
      </section>
    </main>
  </div>

  <footer class="foot">
    <div class="foot-in">
      <a class="logo" href="index.html"><img src="mark-light.svg" alt="" width="22" height="22"><span>Prodline</span></a>
      <nav class="foot-links" aria-label="Footer">
        <a href="index.html#how">How it works</a><a href="index.html#features">Features</a><a href="docs.html">Docs</a><a href="faq.html">FAQ &amp; support</a><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="impressum.html">Impressum</a><a href="mailto:{SUPPORT}">Contact</a>
      </nav>
      <p class="copy">© 2026 Prodline</p>
    </div>
  </footer>
</body>
</html>
'''

OUT.write_text(PAGE)
print(f"wrote {OUT.relative_to(ROOT)}: {len(kinds)} integrations")
