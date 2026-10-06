#!/usr/bin/env python3
"""Builds Prodline's own metrics feed (the app's metrics API format, see docs/API.md).

Run by .github/workflows/metrics.yml, which publishes the result to the `metrics` branch:
    https://raw.githubusercontent.com/expbsn/prodline/metrics/metrics.json

What it reports (all from the repository itself):
    visits        GitHub repo page views, accumulated across runs. Needs a token with read access to
                  repository traffic (secret METRICS_TOKEN); left out without one.
    revenue       0 until Prodline sells anything.
    extras        github_stars, forks, commits, goals_done, goals_open, open_issues
    history       one point per day for the last 30 days (stars, commits, visits)

Local run:  python3 tools/prodline_metrics.py --repo expbsn/prodline --out /tmp/metrics.json
"""

import argparse
import json
import os
import subprocess
import urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone

API = "https://api.github.com"


def get(path, token=None, accept="application/vnd.github+json"):
    req = urllib.request.Request(API + path, headers={"Accept": accept, "User-Agent": "prodline-metrics"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def paged(path, token=None, accept="application/vnd.github+json"):
    out, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        batch = get(f"{path}{sep}per_page=100&page={page}", token, accept)
        out += batch
        if len(batch) < 100:
            return out
        page += 1


def day(d):
    return d.strftime("%Y-%m-%d")


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("REPO", "expbsn/prodline"))
    ap.add_argument("--previous", help="last published metrics.json (keeps visits beyond GitHub's 14 days)")
    ap.add_argument("--out", default="metrics.json")
    args = ap.parse_args()
    token = os.environ.get("GITHUB_TOKEN") or None
    traffic_token = os.environ.get("TRAFFIC_TOKEN") or None
    now = datetime.now(timezone.utc).replace(microsecond=0)

    repo = get(f"/repos/{args.repo}", token)

    # Stars over time (starred_at needs the star+json media type).
    stars = paged(f"/repos/{args.repo}/stargazers", token, "application/vnd.github.star+json")
    star_days = Counter(s["starred_at"][:10] for s in stars if s.get("starred_at"))

    # Commits per day from the checked-out history (falls back to the API's count if git isn't there).
    try:
        dates = subprocess.run(["git", "log", "--format=%cI"], capture_output=True, text=True, check=True).stdout.split()
        commit_days = Counter(datetime.fromisoformat(d).astimezone(timezone.utc).strftime("%Y-%m-%d") for d in dates)
    except Exception:
        commit_days = Counter()

    # Goals from prodline.json in the working tree.
    goals_done = goals_open = 0
    if os.path.exists("prodline.json"):
        plan = json.load(open("prodline.json"))
        goals_done = sum(1 for g in plan.get("goals", []) if g.get("done"))
        goals_open = len(plan.get("goals", [])) - goals_done

    # Page views: GitHub only keeps 14 days, so earlier days are carried over from the last feed.
    views = {}
    if args.previous and os.path.exists(args.previous):
        try:
            views = json.load(open(args.previous)).get("_views", {})
        except ValueError:
            views = {}
    has_views = bool(views)
    if traffic_token:
        try:
            for v in get(f"/repos/{args.repo}/traffic/views", traffic_token).get("views", []):
                views[v["timestamp"][:10]] = v["count"]
            has_views = True
        except Exception as e:  # missing permission: publish without visits rather than fail
            print(f"traffic unavailable: {e}")

    def cumulative(counter, through):
        return sum(n for d, n in counter.items() if d <= through)

    def metrics_at(through):
        m = []
        if has_views:
            m.append({"key": "visits", "value": cumulative(views, through)})
        m.append({"key": "revenue", "value": 0, "unit": "USD"})
        m.append({"key": "github_stars", "value": cumulative(star_days, through)})
        m.append({"key": "commits", "value": cumulative(commit_days, through)})
        return m

    history = []
    for back in range(30, 0, -1):
        d = now - timedelta(days=back)
        history.append({"asOf": iso(d.replace(hour=23, minute=59, second=0)), "metrics": metrics_at(day(d))})

    current = metrics_at(day(now))
    # Current-only numbers (no history needed).
    current.append({"key": "forks", "value": repo.get("forks_count", 0)})
    current.append({"key": "open_issues", "value": repo.get("open_issues_count", 0)})
    current.append({"key": "goals_done", "value": goals_done})
    current.append({"key": "goals_open", "value": goals_open})
    # Stars from the repo itself are authoritative (the list can lag).
    for m in current:
        if m["key"] == "github_stars":
            m["value"] = repo.get("stargazers_count", m["value"])

    feed = {
        "schemaVersion": 1,
        "project": repo.get("name", args.repo.split("/")[-1]),
        "asOf": iso(now),
        "metrics": current,
        "history": history,
        "_views": views,  # carried to the next run; the app ignores unknown keys
    }
    with open(args.out, "w") as f:
        json.dump(feed, f, indent=2)
    print(f"wrote {args.out}: " + ", ".join(f"{m['key']}={m['value']}" for m in current))


if __name__ == "__main__":
    main()
