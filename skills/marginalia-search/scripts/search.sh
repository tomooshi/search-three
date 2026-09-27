#!/bin/bash
set -euo pipefail

# scripts/search.sh — Marginalia Search API (GET api2.marginalia-search.com/search)
#
# Auth: API-Key header. Free non-commercial key = 1000 queries/day, HARD limit.
# Set MARGINALIA_QUOTA_LIMIT if your key has a different daily quota.
#
# Usage:
#   search.sh [options] "query"
#
# Options:
#   -c COUNT     number of results, 1-100 (default 10)
#   -p PAGE      results page, 1-indexed
#   -d DC        max results per domain, 1-100
#   -t TIMEOUT   query execution timeout in ms, 50-250
#   -f FILTER    use a custom filter configured for this key (see filter.sh)
#   -n NSFW      0 = no filter, 1 = (experimental) reduce extreme results
#
# Query operators (inline, all verified live):
#   "exact phrase"   site:example.com   tld:edu   -excludeterm
#   year>2020  year<1996   format:pdf  format:html
#
# Examples:
#   search.sh "linear b"
#   search.sh -c 20 "site:en.wikipedia.org mycenaean"
#   search.sh "commodore 64 year<1996 -wikipedia"
#   search.sh -f myfilter "retro computing"

COUNT=""
PAGE=""
DC=""
TIMEOUT=""
FILTER=""
NSFW=""

while getopts ":c:p:d:t:f:n:" opt; do
	case "$opt" in
	c) COUNT="$OPTARG" ;;
	p) PAGE="$OPTARG" ;;
	d) DC="$OPTARG" ;;
	t) TIMEOUT="$OPTARG" ;;
	f) FILTER="$OPTARG" ;;
	n) NSFW="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

QUERY="${1:?Usage: search.sh [options] \"query\"}"

API_KEY="${MARGINALIA_API_KEY:-}"
if [ -z "$API_KEY" ] && [ -r "$HOME/.config/marginalia/api_key" ]; then
	API_KEY="$(cat "$HOME/.config/marginalia/api_key")"
fi
if [ -z "$API_KEY" ]; then
	echo "warning: no key found, falling back to shared 'public' key (heavily rate-limited)" >&2
	API_KEY="public"
fi

ARGS=(--get --data-urlencode "query=$QUERY")
[ -n "$COUNT" ] && ARGS+=(--data-urlencode "count=$COUNT")
[ -n "$PAGE" ] && ARGS+=(--data-urlencode "page=$PAGE")
[ -n "$DC" ] && ARGS+=(--data-urlencode "dc=$DC")
[ -n "$TIMEOUT" ] && ARGS+=(--data-urlencode "timeout=$TIMEOUT")
[ -n "$FILTER" ] && ARGS+=(--data-urlencode "filter=$FILTER")
[ -n "$NSFW" ] && ARGS+=(--data-urlencode "nsfw=$NSFW")

RESPONSE="$(curl -s -w "\n%{http_code}" \
	-H "API-Key: $API_KEY" \
	"${ARGS[@]}" \
	"https://api2.marginalia-search.com/search")"

HTTP_CODE="$(echo "$RESPONSE" | tail -n1)"
BODY_OUT="$(echo "$RESPONSE" | sed '$d')"

if [ "$HTTP_CODE" != "200" ]; then
	case "$HTTP_CODE" in
	503)
		if [ "$API_KEY" = "public" ]; then
			echo "Marginalia 503: shared 'public' key is rate-limited; get your own free key (see SKILL.md Setup)" >&2
		else
			echo "Marginalia 503: daily quota hit (hard limit; resets at UTC midnight)" >&2
		fi ;;
	401) echo "Marginalia 401: API key rejected. Check ~/.config/marginalia/api_key or MARGINALIA_API_KEY" >&2 ;;
	*) echo "Marginalia API $HTTP_CODE: $BODY_OUT" >&2 ;;
	esac
	exit 1
fi

# Daily-quota ledger (best-effort). Disable with MARGINALIA_LEDGER=off
if [ "${MARGINALIA_LEDGER:-}" != "off" ]; then
	LEDGER="${MARGINALIA_LEDGER:-${XDG_STATE_HOME:-$HOME/.local/state}/marginalia/usage.jsonl}"
	mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
	TODAY="$(date -u +%Y-%m-%d)"
	printf '{"ts":"%sT%sZ","q":%s}\n' "$TODAY" "$(date -u +%H:%M:%S)" \
		"$(printf '%s' "$QUERY" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
		>>"$LEDGER" 2>/dev/null || true
	USED="$(grep -c "\"ts\":\"$TODAY" "$LEDGER" 2>/dev/null || echo '?')"
	echo "marginalia quota: $USED/${MARGINALIA_QUOTA_LIMIT:-1000} queries today" >&2
fi

echo "$BODY_OUT"
