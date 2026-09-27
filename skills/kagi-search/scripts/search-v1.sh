#!/bin/bash
set -euo pipefail

# scripts/search-v1.sh — Kagi Search API v1 (POST /api/v1/search)
#
# Auth: Bearer (NOT Bot). Body: JSON. Returns search results grouped into
# named arrays under `data` (search, news, related_search, image, ...).
#
# Usage:
#   search-v1.sh [options] "query" [extract_count]
#
# Positional:
#   query            the search query (required)
#   extract_count    results to extract full page content for (0-10).
#                    Enriches the `snippet` field of the top-N results with
#                    full page markdown. Backward-compatible positional arg;
#                    equivalent to -n. Default 0.
#
# Options:
#   -w WORKFLOW      search|images|videos|news|podcasts   (default: search)
#   -n COUNT         same as extract_count positional (0-10)
#   -l LIMIT         cap results returned (1-1024)
#   -p PAGE          page number for pagination (1-10)
#   -j JSON          extra top-level JSON object merged into the body, for
#                    advanced params: lens_id, filters, safe_search, format,
#                    timeout, extract.timeout.
#
# NOTE: the inline `lens` object is documented in the OpenAPI spec but is
# silently IGNORED by the live API (verified 2026-08-10). Use search operators
# (site:, filetype:) or `lens_id` instead. `filters.region` must be lowercase;
# this script lowercases it for you.
#
# Examples:
#   search-v1.sh "kagi api docs"                  # search only
#   search-v1.sh "kagi api docs" 3                # + extract top 3 snippets
#   search-v1.sh -w news "openai" 0               # fresh news results
#   search-v1.sh -l 5 "rust async runtimes"       # cap to 5 results
#   search-v1.sh "site:arxiv.org filetype:pdf transformer scaling laws"
#   search-v1.sh -j '{"lens_id":"academic"}' "transformer scaling laws"
#   search-v1.sh -j '{"filters":{"after":"2026-01-01","region":"us"}}' "llm agents"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKFLOW=""
LIMIT=""
PAGE=""
EXTRA_JSON=""
EXTRACT_COUNT=""

while getopts ":w:n:l:p:j:" opt; do
	case "$opt" in
	w) WORKFLOW="$OPTARG" ;;
	n) EXTRACT_COUNT="$OPTARG" ;;
	l) LIMIT="$OPTARG" ;;
	p) PAGE="$OPTARG" ;;
	j) EXTRA_JSON="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

QUERY="${1:?Usage: search-v1.sh [options] \"query\" [extract_count]}"
# Positional extract_count only if -n not given.
if [ -z "$EXTRACT_COUNT" ]; then EXTRACT_COUNT="${2:-0}"; fi

API_KEY="${KAGI_API_KEY:-}"
if [ -z "$API_KEY" ] && [ -r "$HOME/.config/kagi/api_key" ]; then
	API_KEY="$(cat "$HOME/.config/kagi/api_key")"
fi
if [ -z "$API_KEY" ]; then
	echo "Error: no KAGI_API_KEY env var and no $HOME/.config/kagi/api_key file" >&2
	exit 1
fi

BODY="$(QUERY="$QUERY" WORKFLOW="$WORKFLOW" LIMIT="$LIMIT" PAGE="$PAGE" \
	EXTRACT_COUNT="$EXTRACT_COUNT" EXTRA_JSON="$EXTRA_JSON" python3 <<'PY'
import json, os, sys
body = {"query": os.environ["QUERY"]}
if os.environ.get("WORKFLOW"): body["workflow"] = os.environ["WORKFLOW"]
if os.environ.get("LIMIT"): body["limit"] = int(os.environ["LIMIT"])
if os.environ.get("PAGE"): body["page"] = int(os.environ["PAGE"])
c = int(os.environ.get("EXTRACT_COUNT") or 0)
if c > 0: body["extract"] = {"count": c}
extra = os.environ.get("EXTRA_JSON")
if extra:
    try:
        merge = json.loads(extra)
    except json.JSONDecodeError as e:
        raise SystemExit(f"-j is not valid JSON: {e}")
    if not isinstance(merge, dict):
        raise SystemExit("-j must be a JSON object (e.g. '{\"limit\":5}')")
    body.update(merge)
if "lens" in body:
    print("warning: inline `lens` is ignored by the live Kagi API; "
          "use site:/filetype: operators or lens_id", file=sys.stderr)
f = body.get("filters")
if isinstance(f, dict) and isinstance(f.get("region"), str):
    f["region"] = f["region"].lower()   # API rejects uppercase codes with 400
print(json.dumps(body))
PY
)"

RESPONSE="$(curl -s -w "\n%{http_code}" \
	-H "Authorization: Bearer $API_KEY" \
	-H "Content-Type: application/json" \
	-d "$BODY" \
	"https://kagi.com/api/v1/search")"

HTTP_CODE="$(echo "$RESPONSE" | tail -n1)"
BODY_OUT="$(echo "$RESPONSE" | sed '$d')"

if [ "$HTTP_CODE" != "200" ]; then
	echo "Kagi API $HTTP_CODE: $BODY_OUT" >&2
	exit 1
fi

# Cost ledger (best-effort; never fails the search). Disable with KAGI_LEDGER=off
if [ "${KAGI_LEDGER:-}" != "off" ] && [ -r "$SCRIPT_DIR/_ledger.py" ]; then
	printf '%s' "$BODY_OUT" | KAGI_LEDGER_QUERY="$QUERY" \
		python3 "$SCRIPT_DIR/_ledger.py" search "$EXTRACT_COUNT" 2>/dev/null || true
fi

echo "$BODY_OUT"
