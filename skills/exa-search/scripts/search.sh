#!/bin/bash
set -euo pipefail

# scripts/search.sh — Exa neural search (POST api.exa.ai/search)
#
# Embeddings-based retrieval: phrase the query as a *description of the
# answer*, not keywords ("blog posts where practitioners argue against lazy
# loading" beats "lazy loading criticism").
#
# Cost: $0.007 base (up to 10 results) + $0.001/result above 10.
#       -x adds full page text at $0.001/page.
#
# Usage:
#   search.sh [options] "query"
#
# Options:
#   -n NUM       number of results (default 10; >10 bills extra)
#   -t TYPE      auto | neural | keyword | fast | deep  (default auto)
#   -c CATEGORY  e.g. "research paper", company, news, "personal site",
#                "github", "tweet", pdf, "linkedin profile", "financial report"
#   -d DOMAINS   comma-separated includeDomains
#   -a DATE      startPublishedDate (YYYY-MM-DD)
#   -b DATE      endPublishedDate (YYYY-MM-DD)
#   -x           include full page text in results (contents.text, +$0.001/pg)
#   -j JSON      extra JSON merged into request body (e.g. '{"contents":{"summary":true}}')
#
# Examples:
#   search.sh "startups building anti-detect browsers"
#   search.sh -c "research paper" -a 2024-01-01 "form validation usability studies"
#   search.sh -t keyword "MARGINALIA_API_KEY"          # exact-match needs keyword type
#   search.sh -x -n 5 "essays on digital gardens"      # with full text

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

NUM="" TYPE="" CATEGORY="" DOMAINS="" AFTER="" BEFORE="" TEXT="" EXTRA=""
while getopts ":n:t:c:d:a:b:xj:" opt; do
	case "$opt" in
	n) NUM="$OPTARG" ;;
	t) TYPE="$OPTARG" ;;
	c) CATEGORY="$OPTARG" ;;
	d) DOMAINS="$OPTARG" ;;
	a) AFTER="$OPTARG" ;;
	b) BEFORE="$OPTARG" ;;
	x) TEXT=1 ;;
	j) EXTRA="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
QUERY="${1:?Usage: search.sh [options] \"query\"}"

exa_key

BODY="$(QUERY="$QUERY" NUM="$NUM" TYPE="$TYPE" CATEGORY="$CATEGORY" DOMAINS="$DOMAINS" \
	AFTER="$AFTER" BEFORE="$BEFORE" TEXT="$TEXT" EXTRA="$EXTRA" python3 -c '
import json, os
b = {"query": os.environ["QUERY"]}
if os.environ.get("NUM"): b["numResults"] = int(os.environ["NUM"])
if os.environ.get("TYPE"): b["type"] = os.environ["TYPE"]
if os.environ.get("CATEGORY"): b["category"] = os.environ["CATEGORY"]
if os.environ.get("DOMAINS"): b["includeDomains"] = os.environ["DOMAINS"].split(",")
if os.environ.get("AFTER"): b["startPublishedDate"] = os.environ["AFTER"] + "T00:00:00.000Z"
if os.environ.get("BEFORE"): b["endPublishedDate"] = os.environ["BEFORE"] + "T23:59:59.999Z"
if os.environ.get("TEXT"): b["contents"] = {"text": True}
extra = os.environ.get("EXTRA")
if extra:
    m = json.loads(extra)
    if not isinstance(m, dict): raise SystemExit("-j must be a JSON object")
    b.update(m)
print(json.dumps(b))')"

exa_post search "$BODY" search "$QUERY"
