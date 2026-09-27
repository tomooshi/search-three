#!/usr/bin/env python3
"""Append one Kagi API usage record to the local cost ledger.

Reads the raw API response body on stdin so it can bill actual units rather
than requested ones. Never fails the caller: any error exits 0 silently.

Usage:  _ledger.py <endpoint> <requested_units>
        endpoint         "search" | "extract"
        requested_units  search: extract.count requested (0 if none)
                         extract: number of URLs submitted
        query text is passed via $KAGI_LEDGER_QUERY

Rates (USD, override via env):
  KAGI_RATE_SEARCH   default 0.012   ($12 / 1K requests)
  KAGI_RATE_EXTRACT  default 0.004   ($4  / 1K pages)

Ledger path: $KAGI_LEDGER, else ${XDG_STATE_HOME:-~/.local/state}/kagi/usage.jsonl
"""

import json
import os
import sys
from datetime import datetime, timezone


def ledger_path() -> str:
    explicit = os.environ.get("KAGI_LEDGER")
    if explicit:
        return explicit
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "kagi", "usage.jsonl")


def main() -> None:
    endpoint = sys.argv[1]
    requested = int(sys.argv[2] or 0)
    body = sys.stdin.read()

    try:
        parsed = json.loads(body)
    except Exception:
        parsed = None  # format=markdown returns text/markdown, not JSON

    searches = 1 if endpoint == "search" else 0
    pages = requested
    pages_ok = None
    trace = None

    if isinstance(parsed, dict):
        trace = (parsed.get("meta") or {}).get("trace")
        data = parsed.get("data")
        if endpoint == "search" and requested > 0 and isinstance(data, dict):
            # Extraction applies to the top-N web results; Kagi does not bill
            # when there was nothing to extract.
            available = len(data.get("search") or [])
            pages = min(requested, available)
        elif endpoint == "extract" and isinstance(data, list):
            pages = len(data)
            pages_ok = sum(1 for p in data if isinstance(p, dict) and p.get("markdown"))

    rate_search = float(os.environ.get("KAGI_RATE_SEARCH", "0.012"))
    rate_extract = float(os.environ.get("KAGI_RATE_EXTRACT", "0.004"))
    usd = round(searches * rate_search + pages * rate_extract, 6)

    record = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "ep": endpoint,
        "searches": searches,
        "pages": pages,
        "usd": usd,
    }
    if pages_ok is not None and pages_ok != pages:
        record["pages_ok"] = pages_ok
    if trace:
        record["trace"] = trace
    q = os.environ.get("KAGI_LEDGER_QUERY")
    if q:
        record["q"] = q[:120]

    path = ledger_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    # Records include query text, so keep the ledger owner-only. O_APPEND makes
    # single-line writes atomic across concurrent agent sessions.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # cost tracking must never break a search
    sys.exit(0)
