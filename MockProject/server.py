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

    def do_GET(self):
        url, parts, q = self.route()
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
            else:
                return self.send_json(400, {"error": "type must be sale, visits or viral"})
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
