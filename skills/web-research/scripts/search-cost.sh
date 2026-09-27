#!/bin/bash
# scripts/search-cost.sh — summarize local usage ledgers for all three engines.
#
# The engine scripts append one JSON line per call to:
#   ${XDG_STATE_HOME:-~/.local/state}/{kagi,exa,marginalia}/usage.jsonl
# (override per engine with KAGI_LEDGER / EXA_LEDGER / MARGINALIA_LEDGER).
#
# Usage:
#   search-cost.sh          # today / this month / all time
#
# Kagi and Exa report estimated USD; Marginalia reports query count against
# its daily quota (UTC window, MARGINALIA_QUOTA_LIMIT, default 1000).
# Ledgers only see calls made through these scripts — the providers'
# dashboards are the source of truth for billing.

exec python3 - <<'PY'
import json, os
from datetime import datetime, timezone

state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
limit = int(os.environ.get("MARGINALIA_QUOTA_LIMIT", "1000"))

def path(engine):
    p = os.environ.get(f"{engine.upper()}_LEDGER")
    return p if p and p != "off" else os.path.join(state, engine, "usage.jsonl")

def records(engine):
    try:
        with open(path(engine)) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    ts = datetime.fromisoformat(r["ts"].replace("Z", "+00:00"))
                    yield ts, r
                except Exception:
                    continue
    except FileNotFoundError:
        return

now_local = datetime.now().astimezone()
now_utc = datetime.now(timezone.utc)
day_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
month_local = day_local.replace(day=1)
day_utc = now_utc.replace(hour=0, minute=0, second=0, microsecond=0)

def money(engine):
    out = {"today": [0.0, 0], "month": [0.0, 0], "all": [0.0, 0]}
    for ts, r in records(engine):
        usd = float(r.get("usd") or 0)
        for name, cutoff in (("today", day_local), ("month", month_local), ("all", None)):
            if cutoff is None or ts >= cutoff:
                out[name][0] += usd
                out[name][1] += 1
    return out

k, e = money("kagi"), money("exa")
m = {"today": 0, "month": 0, "all": 0}
for ts, _ in records("marginalia"):
    m["all"] += 1
    if ts >= month_local: m["month"] += 1
    if ts >= day_utc: m["today"] += 1

print(f"{'':8} {'kagi':>16} {'exa':>16} {'marginalia':>18}")
for name in ("today", "month", "all"):
    marg = f"{m[name]}/{limit} (UTC)" if name == "today" else str(m[name])
    print(f"{name:8} {'$%.3f (%d)' % tuple(k[name]):>16} {'$%.3f (%d)' % tuple(e[name]):>16} {marg:>18}")
if m["today"] >= 0.8 * limit:
    print(f"warning: marginalia at {100 * m['today'] // limit}% of its daily HARD limit")
print(f"ledgers: {path('kagi')}, {path('exa')}, {path('marginalia')}")
PY
