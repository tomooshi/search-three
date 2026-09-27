#!/bin/bash
set -euo pipefail

# scripts/filter.sh — manage custom filters for a Marginalia API key.
# Filter management does NOT count against the search quota ledger.
# The shared 'public' key cannot manage filters.
#
# Usage:
#   filter.sh list                  # list configured filter names
#   filter.sh get NAME              # print the XML definition of NAME
#   filter.sh create NAME FILE.xml  # create/replace filter NAME from an XML file ('-' = stdin)
#   filter.sh delete NAME
#
# Filter XML reference (all elements optional):
#   <filter>
#     <domains-include>example.com *.example.org</domains-include>
#     <domains-exclude>spam.example</domains-exclude>
#     <domains-promote amount="1.0">good.example</domains-promote>  <!-- negative demotes -->
#     <temporal-bias>OLD</temporal-bias>          <!-- OLD | RECENT | NONE -->
#     <terms-require>foo bar</terms-require>
#     <terms-exclude>baz</terms-exclude>
#     <terms-promote amount="5.0">quux</terms-promote>
#     <limit param="year" type="lt" value="1996"/>   <!-- estimated pub year (janky) -->
#     <limit param="quality" type="eq" value="5"/>   <!-- js-heaviness metric -->
#     <limit param="size" type="gt" value="100"/>    <!-- docs on the domain -->
#     <limit param="rank" type="gt" value="20"/>     <!-- pagerank 0-255 -->
#   </filter>

CMD="${1:?Usage: filter.sh list|get|create|delete ...}"

API_KEY="${MARGINALIA_API_KEY:-}"
if [ -z "$API_KEY" ] && [ -r "$HOME/.config/marginalia/api_key" ]; then
	API_KEY="$(cat "$HOME/.config/marginalia/api_key")"
fi
if [ -z "$API_KEY" ]; then
	echo "Error: filter management needs a real key (MARGINALIA_API_KEY or ~/.config/marginalia/api_key)" >&2
	exit 1
fi

BASE="https://api2.marginalia-search.com/filter"

call() {
	local method="$1" url="$2"; shift 2
	local resp code
	resp="$(curl -s -w "\n%{http_code}" -X "$method" -H "API-Key: $API_KEY" "$@" "$url")"
	code="$(echo "$resp" | tail -n1)"
	echo "$resp" | sed '$d'
	case "$code" in 2*) ;; *) echo "Marginalia API $code" >&2; exit 1 ;; esac
}

case "$CMD" in
list)
	call GET "$BASE"
	;;
get)
	NAME="${2:?Usage: filter.sh get NAME}"
	call GET "$BASE/$NAME"
	;;
create)
	NAME="${2:?Usage: filter.sh create NAME FILE.xml}"
	FILE="${3:?Usage: filter.sh create NAME FILE.xml (use '-' for stdin)}"
	call POST "$BASE/$NAME" -H "Content-Type: application/xml" --data-binary "@$FILE"
	echo "filter '$NAME' created" >&2
	;;
delete)
	NAME="${2:?Usage: filter.sh delete NAME}"
	call DELETE "$BASE/$NAME"
	echo "filter '$NAME' deleted" >&2
	;;
*)
	echo "Unknown command: $CMD (list|get|create|delete)" >&2
	exit 2
	;;
esac
