#!/usr/bin/env python3
"""
Prodline mock project server.

Simulates several "projects" that expose the Prodline metrics API, with live traffic,
occasional sales, hourly history and failure modes, so the app can be tested end to end.

    python3 MockProject/server.py              # http://127.0.0.1:8787
    python3 MockProject/server.py --port 9000 --host 0.0.0.0

Endpoints
    GET  /health
    GET  /projects/<slug>/metrics[?since=ISO8601][&fail=CODE][&delay=MS]
    POST /projects/<slug>/events   {"type": "sale", "amount": 19.99}
                                   {"type": "visits", "count": 500}
                                   {"type": "viral"}            (+25k social views)
                                   {"type": "goal", "id": "onboarding", "done": true}
                                   {"type": "close_issue" | "reopen_issue", "number": 12}   (mock GitHub)

    Mock GitHub API (point the app's githubAPIBase at http://host:port/github):
    GET  /github/repos/demo/<repo>[/readme|/milestones|/issues|/commits|/contents/prodline.json]
    POST /projects/<slug>/events   {"type": "plan_goal", "id": "launch-post", "done": true}   (edits the mock prodline.json)

All project endpoints need  Authorization: Bearer <key>.  No third-party dependencies.
"""

import argparse
import json
import math
import random
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# Must match DemoData.projects in the app.
PROJECTS = {
    "habit-hero":  dict(name="Habit Hero",  key="hh_live_demo", started_days_ago=9,  visits_per_day=420, growth=1.16, social_ratio=2.4, price=4.99,  conversion=0.012, fail_rate=0.0),
    "pixel-quest": dict(name="Pixel Quest", key="pq_live_demo", started_days_ago=23, visits_per_day=900, growth=1.05, social_ratio=6.0, price=2.99,  conversion=0.020, fail_rate=0.0),
    "side-shop":   dict(name="Side Shop",   key="ss_live_demo", started_days_ago=2,  visits_per_day=150, growth=1.40, social_ratio=0.8, price=29.00, conversion=0.006, fail_rate=0.0),
    "flaky-app":   dict(name="Flaky App",   key="fa_live_demo", started_days_ago=5,  visits_per_day=260, growth=1.10, social_ratio=1.5, price=9.99,  conversion=0.010, fail_rate=0.5),
}

LIVE_BOOST = 40          # live traffic is boosted so changes are visible every poll
HISTORY_DAYS = 7
SERVER_START = datetime.now(timezone.utc)
LOCK = threading.Lock()
EVENTS = {slug: [] for slug in PROJECTS}   # (timestamp, metric, amount)

# Goals the project reports through its API ("checkpoint" = position in the app's deadline list).
GOALS = {
    "habit-hero": [
        {"id": "onboarding", "title": "Onboarding flow live", "checkpoint": 3, "done": False},
        {"id": "streak-share", "title": "Shareable streak card", "checkpoint": 3, "done": True},
        {"id": "signups-500", "title": "500 signups", "checkpoint": 4,
         "metric": {"key": "signups", "target": 500}},
    ],
}

# A tiny GitHub: one repo per demo project that links one.
def _days_ago(n):
    return iso(datetime.now(timezone.utc) - timedelta(days=n)).replace(".000Z", "Z")

GITHUB = {
    "side-shop": {
        "repo": {"description": "A one-page shop for limited print runs.", "pushed_at": None},
        "readme": "# Side Shop\nSell limited poster runs. Next.js storefront, Stripe checkout, email receipts.\n",
        "milestones": [
            {"number": 1, "title": "MVP", "state": "open", "due_on": None},
            {"number": 2, "title": "Payments", "state": "open", "due_on": None},
        ],
        "issues": [
            {"number": 11, "title": "Product grid", "state": "closed", "milestone": 1, "labels": []},
            {"number": 12, "title": "Cart drawer", "state": "open", "milestone": 1, "labels": []},
            {"number": 13, "title": "Stripe checkout", "state": "open", "milestone": 2, "labels": []},
            {"number": 14, "title": "Bump deps", "state": "open", "milestone": None, "labels": [], "pull": True},
            {"number": 15, "title": "Order confirmation email", "state": "open", "milestone": None, "labels": ["prodline"]},
        ],
        "last_commit_days_ago": 3,
        "plan": {
            "version": 1,
            "goals": [
                {"id": "shipping-rates", "title": "Add shipping rates table", "checkpoint": 3, "done": False},
                {"id": "launch-post", "title": "Draft launch post", "checkpoint": 4, "done": False},
            ],
        },
    },
}


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_iso(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def start_of(slug):
    day0 = SERVER_START.replace(hour=0, minute=0, second=0, microsecond=0)
    return day0 - timedelta(days=PROJECTS[slug]["started_days_ago"])


def model(slug, at):
    """Deterministic cumulative totals at time `at` (before live events)."""
    p = PROJECTS[slug]
    t = max(0.0, (at - start_of(slug)).total_seconds() / 86400)
    g = math.log(p["growth"])
    visits = p["visits_per_day"] * (math.exp(g * t) - 1) / g
    # Daily rhythm: more traffic in the evening.
    visits += p["visits_per_day"] * 0.12 * (1 - math.cos(2 * math.pi * t)) / (2 * math.pi)
    social = visits * p["social_ratio"] * (1 + 0.05 * math.sin(t))
    revenue = visits * p["conversion"] * p["price"]
    signups = visits * 0.045
    return dict(visits=visits, social_views=social, revenue=revenue, signups=signups)


def totals(slug, at):
    v = model(slug, at)
    with LOCK:
        for ts, metric, amount in EVENTS[slug]:
            if ts <= at:
                v[metric] += amount
                if metric == "visits":
                    v["signups"] += amount * 0.045
    return v


def metrics_list(v):
    return [
        {"key": "visits", "value": round(v["visits"])},
        {"key": "social_views", "value": round(v["social_views"])},
        {"key": "revenue", "value": round(v["revenue"], 2), "unit": "USD"},
        {"key": "signups", "value": round(v["signups"])},
    ]


def github_issue(slug, i):
    out = {"number": i["number"], "title": i["title"], "state": i["state"],
           "html_url": f"https://github.com/demo/{slug}/issues/{i['number']}",
           "labels": [{"name": n} for n in i["labels"]],
           "milestone": {"number": i["milestone"]} if i["milestone"] else None}
    if i.get("pull"):
        out["pull_request"] = {"url": "https://api.github.com/pr"}
    return out


def payload(slug, since):
    now = datetime.now(timezone.utc)
    begin = max(start_of(slug), now - timedelta(days=HISTORY_DAYS))
    if since and since > begin:
        begin = since
    # Hourly points on the hour, strictly after `begin`.
    t = begin.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
    history = []
    while t < now:
        history.append({"asOf": iso(t), "metrics": metrics_list(totals(slug, t))})
        t += timedelta(hours=1)
    return {
        "schemaVersion": 1,
        "project": PROJECTS[slug]["name"],
        "asOf": iso(now),
        "metrics": metrics_list(totals(slug, now)),
        "history": history,
        **({"goals": GOALS[slug]} if slug in GOALS else {}),
    }


def simulate():
    """Background live traffic + occasional sales."""
    while True:
        time.sleep(2)
        now = datetime.now(timezone.utc)
        with LOCK:
            for slug, p in PROJECTS.items():
                rate = p["visits_per_day"] / 86400 * 2 * LIVE_BOOST
                visits = sum(1 for _ in range(int(rate * 3) + 1) if random.random() < rate / (int(rate * 3) + 1))
                if visits:
                    EVENTS[slug].append((now, "visits", visits))
                    EVENTS[slug].append((now, "social_views", visits * p["social_ratio"]))
                if random.random() < 0.03:
                    EVENTS[slug].append((now, "revenue", p["price"]))


class Handler(BaseHTTPRequestHandler):
    server_version = "ProdlineMock/1.0"

    def log_message(self, fmt, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {self.address_string()} {fmt % args}", flush=True)

    def send_json(self, code, body, headers=None):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def route(self):
        url = urlparse(self.path)
        parts = [p for p in url.path.split("/") if p]
        return url, parts, parse_qs(url.query)

    def authorized(self, slug):
        auth = self.headers.get("Authorization", "")
        return auth == f"Bearer {PROJECTS[slug]['key']}"

    def github(self, parts):
        # parts: ["github", "repos", "demo", "<repo>", optional resource]
        if len(parts) < 4 or parts[1] != "repos" or parts[3] not in GITHUB:
            return self.send_json(404, {"message": "Not Found"})
        repo = GITHUB[parts[3]]
        res = parts[4] if len(parts) > 4 else ""
        if res == "":
            return self.send_json(200, {**repo["repo"], "pushed_at": _days_ago(repo["last_commit_days_ago"])})
        if res == "readme":
            data = repo["readme"].encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return self.wfile.write(data)
        if res == "milestones":
            return self.send_json(200, repo["milestones"])
        if res == "issues":
            return self.send_json(200, [github_issue(parts[3], i) for i in repo["issues"]])
        if res == "contents" and len(parts) > 5 and parts[5] == "prodline.json":
            if "plan" not in repo:
                return self.send_json(404, {"message": "Not Found"})
            data = json.dumps(repo["plan"]).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return self.wfile.write(data)
        if res == "commits":
            return self.send_json(200, [{"commit": {"committer": {"date": _days_ago(repo["last_commit_days_ago"])}}}])
        return self.send_json(404, {"message": "Not Found"})

    def do_GET(self):
        url, parts, q = self.route()
        if parts and parts[0] == "github":
            return self.github(parts)
        if parts == ["health"]:
            return self.send_json(200, {"ok": True, "projects": list(PROJECTS), "started": iso(SERVER_START)})
        if len(parts) != 3 or parts[0] != "projects" or parts[2] != "metrics":
            return self.send_json(404, {"error": "not found"})
        slug = parts[1]
        if slug not in PROJECTS:
            return self.send_json(404, {"error": f"unknown project {slug}"})
        if not self.authorized(slug):
            return self.send_json(401, {"error": "invalid api key"})
        if "delay" in q:
            time.sleep(int(q["delay"][0]) / 1000)
        if "fail" in q:
            code = int(q["fail"][0])
            if code == 200:
                data = b"{not json"
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                return self.wfile.write(data)
            return self.send_json(code, {"error": "forced failure"}, {"Retry-After": "5"} if code == 429 else None)
        if random.random() < PROJECTS[slug]["fail_rate"]:
            return self.send_json(503, {"error": "temporarily unavailable"})
        since = None
        if "since" in q:
            try:
                since = parse_iso(q["since"][0])
            except ValueError:
                return self.send_json(400, {"error": "bad since"})
        self.send_json(200, payload(slug, since))

    def do_POST(self):
        url, parts, q = self.route()
        if len(parts) != 3 or parts[0] != "projects" or parts[2] != "events" or parts[1] not in PROJECTS:
            return self.send_json(404, {"error": "not found"})
        slug = parts[1]
        if not self.authorized(slug):
            return self.send_json(401, {"error": "invalid api key"})
        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self.send_json(400, {"error": "bad json"})
        now = datetime.now(timezone.utc)
        kind = body.get("type")
        with LOCK:
            if kind == "sale":
                EVENTS[slug].append((now, "revenue", float(body.get("amount", PROJECTS[slug]["price"]))))
            elif kind == "visits":
                EVENTS[slug].append((now, "visits", int(body.get("count", 100))))
            elif kind == "viral":
                EVENTS[slug].append((now, "social_views", 25000))
                EVENTS[slug].append((now, "visits", 1500))
            elif kind == "goal":
                for g in GOALS.get(slug, []):
                    if g["id"] == body.get("id"):
                        g["done"] = bool(body.get("done", True))
            elif kind == "plan_goal":
                for g in GITHUB.get(slug, {}).get("plan", {}).get("goals", []):
                    if g["id"] == body.get("id"):
                        g["done"] = bool(body.get("done", True))
            elif kind == "reopen_issue":
                for i in GITHUB.get(slug, {}).get("issues", []):
                    if i["number"] == body.get("number"):
                        i["state"] = "open"
            elif kind == "close_issue":
                for i in GITHUB.get(slug, {}).get("issues", []):
                    if i["number"] == body.get("number"):
                        i["state"] = "closed"
                GITHUB.get(slug, {})["last_commit_days_ago"] = 0
            else:
                return self.send_json(400, {"error": "type must be sale, visits, viral, goal or close_issue"})
        self.send_json(200, {"ok": True})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args()
    threading.Thread(target=simulate, daemon=True).start()
    print(f"Prodline mock server on http://{args.host}:{args.port}")
    for slug, p in PROJECTS.items():
        print(f"  {p['name']:<12} /projects/{slug}/metrics   key={p['key']}   fail_rate={p['fail_rate']}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
