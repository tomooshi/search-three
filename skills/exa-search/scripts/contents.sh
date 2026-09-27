#!/bin/bash
set -euo pipefail

# scripts/contents.sh — Exa page contents (POST api.exa.ai/contents)
# $0.001/page — 4x cheaper than Kagi extract; often succeeds where Kagi's
# crawler fails (serves from Exa's crawl cache; check statuses[].source).
#
# Usage:
#   contents.sh URL [URL ...]
#   contents.sh -s URL          # + AI summary (+$0.001/page)
#   contents.sh -l URL          # livecrawl=always (fresh fetch, not cache)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

SUMMARY="" LIVE=""
while getopts ":sl" opt; do
	case "$opt" in
	s) SUMMARY=1 ;;
	l) LIVE=1 ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "Usage: contents.sh [-s] [-l] URL [URL ...]" >&2; exit 2; }

exa_key

BODY="$(SUMMARY="$SUMMARY" LIVE="$LIVE" python3 -c '
import json, os, sys
b = {"urls": sys.argv[1:], "text": True}
if os.environ.get("SUMMARY"): b["summary"] = True
if os.environ.get("LIVE"): b["livecrawl"] = "always"
print(json.dumps(b))' "$@")"

exa_post contents "$BODY" contents "$1"
