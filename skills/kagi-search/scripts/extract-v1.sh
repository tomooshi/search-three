#!/bin/bash
set -euo pipefail

# scripts/extract-v1.sh — Kagi Extract API v1 (POST /api/v1/extract)
#
# Fetches page content as clean markdown for up to 10 URLs in one call.
# Auth: Bearer. URLs must be HTTPS. Use this when you already have URL(s)
# and want the readable content — no search round trip needed.
#
# Usage:
#   extract-v1.sh [-t SECONDS] URL [URL ...]
#
#   -t SECONDS   total time budget for the concurrent bulk fetch (0.5-10)
#
# Examples:
#   extract-v1.sh https://help.kagi.com/kagi/api/overview.html
#   extract-v1.sh https://a.com/x https://b.com/y   # batch, 1-10 URLs
#   extract-v1.sh https://x.com/OpenAI/status/2085434712429052386  # tweets work
#   extract-v1.sh -t 8 https://slow.example.com/page
#
# Response shape:
#   { "meta": {trace, ms, node},
#     "data": [ {"url": "...", "markdown": "...", "error": "..."?} ],
#     "errors": [ {code, url, message, location} ]?  }
#
# Per-URL failures arrive as data[i].error with HTTP 200 — always check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TIMEOUT=""
while getopts ":t:" opt; do
	case "$opt" in
	t) TIMEOUT="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

if [ "$#" -lt 1 ]; then
	echo "Usage: extract-v1.sh [-t SECONDS] URL [URL ...]   (1-10 HTTPS URLs)" >&2
	exit 2
fi

API_KEY="${KAGI_API_KEY:-}"
if [ -z "$API_KEY" ] && [ -r "$HOME/.config/kagi/api_key" ]; then
	API_KEY="$(cat "$HOME/.config/kagi/api_key")"
fi
if [ -z "$API_KEY" ]; then
	echo "Error: no KAGI_API_KEY env var and no $HOME/.config/kagi/api_key file" >&2
	exit 1
fi

BODY="$(TIMEOUT="$TIMEOUT" python3 - "$@" <<'PY'
import json, os, sys
urls = sys.argv[1:]
if not (1 <= len(urls) <= 10):
    raise SystemExit("extract accepts 1-10 URLs")
body = {"pages": [{"url": u} for u in urls]}
if os.environ.get("TIMEOUT"):
    body["timeout"] = float(os.environ["TIMEOUT"])  # 0.5-10, clamped by API
print(json.dumps(body))
PY
)"

RESPONSE="$(curl -s -w "\n%{http_code}" \
	-H "Authorization: Bearer $API_KEY" \
	-H "Content-Type: application/json" \
	-d "$BODY" \
	"https://kagi.com/api/v1/extract")"

HTTP_CODE="$(echo "$RESPONSE" | tail -n1)"
BODY_OUT="$(echo "$RESPONSE" | sed '$d')"

if [ "$HTTP_CODE" != "200" ]; then
	echo "Kagi API $HTTP_CODE: $BODY_OUT" >&2
	exit 1
fi

# Cost ledger (best-effort; never fails the extract). Disable with KAGI_LEDGER=off
if [ "${KAGI_LEDGER:-}" != "off" ] && [ -r "$SCRIPT_DIR/_ledger.py" ]; then
	printf '%s' "$BODY_OUT" | KAGI_LEDGER_QUERY="$1" \
		python3 "$SCRIPT_DIR/_ledger.py" extract "$#" 2>/dev/null || true
fi

echo "$BODY_OUT"
