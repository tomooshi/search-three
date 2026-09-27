#!/bin/bash
set -euo pipefail

# scripts/find-similar.sh — Exa link similarity (POST api.exa.ai/findSimilar)
# Give it a URL, get semantically similar pages. $0.007/request.
# No equivalent exists in Kagi or Marginalia — this is Exa-only capability.
#
# Usage:
#   find-similar.sh [options] URL
#
# Options:
#   -n NUM     number of results (default 10)
#   -e         exclude the source domain from results
#   -x         include full page text (+$0.001/page)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

NUM="" EXCL="" TEXT=""
while getopts ":n:ex" opt; do
	case "$opt" in
	n) NUM="$OPTARG" ;;
	e) EXCL=1 ;;
	x) TEXT=1 ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
URL="${1:?Usage: find-similar.sh [options] URL}"

exa_key

BODY="$(URL="$URL" NUM="$NUM" EXCL="$EXCL" TEXT="$TEXT" python3 -c '
import json, os
b = {"url": os.environ["URL"]}
if os.environ.get("NUM"): b["numResults"] = int(os.environ["NUM"])
if os.environ.get("EXCL"): b["excludeSourceDomain"] = True
if os.environ.get("TEXT"): b["contents"] = {"text": True}
print(json.dumps(b))')"

exa_post findSimilar "$BODY" findSimilar "$URL"
