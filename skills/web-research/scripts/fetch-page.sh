#!/bin/bash
set -uo pipefail

# scripts/fetch-page.sh — page-to-markdown with automatic fallback ladder.
#
# Tries each rung in order until one yields content:
#   0. exa       Exa contents API ($0.001) — cheapest; serves from Exa's crawl
#                cache (fast, sometimes stale); succeeds on some pages Kagi
#                can't crawl. NOT for X/Twitter (use kagi).
#   1. kagi      Kagi extract API ($0.004) — best quality, handles X/Twitter
#   2. curl      plain HTTP + local bs4 extraction — free, no JS
#   3. playwright headless Chromium render + local extraction — free, runs JS,
#                gets past mild bot-walls (NOT Cloudflare turnstile/logins)
#   4. camoufox  anti-detect Firefox (daijro/camoufox) + local extraction —
#                free but heavy (~10s, ~200MB RAM); fingerprint-spoofed, for
#                pages that block plain headless browsers
#   5. wayback   archive.org closest snapshot + local extraction — free,
#                for dead pages and walls nothing else beats (stale content)
#
# Usage:
#   fetch-page.sh [options] URL
#
# Options:
#   -m METHODS  comma-separated ladder override, e.g. -m curl,playwright
#               (default: exa,kagi,curl,playwright,camoufox,wayback;
#                X/Twitter URLs auto-skip the exa rung)
#   -t SECS     per-rung timeout (default 25)
#
# Env:
#   FETCH_PYTHON       python used for local extraction (needs beautifulsoup4)
#                      and the playwright rung (default: python3)
#   CAMOUFOX_PYTHON    python with the camoufox package (default:
#                      ~/.venvs/camoufox/bin/python if present, else FETCH_PYTHON)
#   SEARCH_SKILLS_DIR  directory holding the sibling engine skills
#                      (default: two levels up from this script)
#
# Output: one JSON object on stdout:
#   {"url", "method", "title", "markdown", "attempts": {rung: "error", ...}}
# Exit 1 with {"url", "error", "attempts"} if every rung fails.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SEARCH_SKILLS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KAGI_SCRIPTS="$SKILLS_ROOT/kagi-search/scripts"
EXA_SCRIPTS="$SKILLS_ROOT/exa-search/scripts"

METHODS="exa,kagi,curl,playwright,camoufox,wayback"
TIMEOUT=25
PY="${FETCH_PYTHON:-python3}"
if [ -z "${CAMOUFOX_PYTHON:-}" ]; then
	if [ -x "$HOME/.venvs/camoufox/bin/python" ]; then
		CAMOUFOX_PYTHON="$HOME/.venvs/camoufox/bin/python"
	else
		CAMOUFOX_PYTHON="$PY"
	fi
fi

while getopts ":m:t:" opt; do
	case "$opt" in
	m) METHODS="$OPTARG" ;;
	t) TIMEOUT="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

URL="${1:?Usage: fetch-page.sh [options] URL}"

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

ATTEMPTS="{}"

note_failure() { # rung message
	ATTEMPTS="$(ATT="$ATTEMPTS" RUNG="$1" MSG="$2" python3 -c '
import json, os
a = json.loads(os.environ["ATT"]); a[os.environ["RUNG"]] = os.environ["MSG"][:200]
print(json.dumps(a))')"
}

emit_success() { # rung json_file_with_title_markdown
	URL="$URL" RUNG="$1" ATT="$ATTEMPTS" python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
if not (d.get("markdown") or "").strip():
    sys.exit(3)  # empty extraction = not a success
print(json.dumps({"url": os.environ["URL"], "method": os.environ["RUNG"],
                  "title": d.get("title", ""), "markdown": d["markdown"],
                  "attempts": json.loads(os.environ["ATT"])}))' "$2"
}

try_exa() {
	case "$URL" in
	*//x.com/*|*//twitter.com/*|*//www.x.com/*|*//www.twitter.com/*)
		note_failure exa "skipped for X/Twitter (kagi renders tweets)"; return 1 ;;
	esac
	[ -f "$EXA_SCRIPTS/contents.sh" ] || { note_failure exa "exa-search skill not found at $EXA_SCRIPTS"; return 1; }
	if ! bash "$EXA_SCRIPTS/contents.sh" "$URL" >"$TMPD/exa.json" 2>"$TMPD/exa.err"; then
		note_failure exa "$(head -c 200 "$TMPD/exa.err")"
		return 1
	fi
	if ! python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
item = (d.get("results") or [{}])[0]
status = (d.get("statuses") or [{}])[0]
text = item.get("text") or ""
if status.get("status") != "success" or len(text.strip()) < 200:
    raise SystemExit(status.get("error") or f"thin content ({len(text)} chars)")
json.dump({"title": item.get("title",""), "markdown": text}, open(sys.argv[2], "w"))' \
		"$TMPD/exa.json" "$TMPD/out.json" 2>"$TMPD/exa.err2"; then
		note_failure exa "$(head -c 200 "$TMPD/exa.err2")"
		return 1
	fi
	emit_success exa "$TMPD/out.json"
}

try_kagi() {
	[ -f "$KAGI_SCRIPTS/extract-v1.sh" ] || { note_failure kagi "kagi-search skill not found at $KAGI_SCRIPTS"; return 1; }
	if ! bash "$KAGI_SCRIPTS/extract-v1.sh" "$URL" >"$TMPD/kagi.json" 2>"$TMPD/kagi.err"; then
		note_failure kagi "$(head -c 200 "$TMPD/kagi.err")"
		return 1
	fi
	if ! python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
item = (d.get("data") or [{}])[0]
if item.get("error") or not (item.get("markdown") or "").strip():
    raise SystemExit(item.get("error") or "empty markdown")
json.dump({"title": "", "markdown": item["markdown"]}, open(sys.argv[2], "w"))' \
		"$TMPD/kagi.json" "$TMPD/out.json" 2>"$TMPD/kagi.err2"; then
		note_failure kagi "$(head -c 200 "$TMPD/kagi.err2")"
		return 1
	fi
	emit_success kagi "$TMPD/out.json"
}

fetch_and_extract() { # fetch_url rung
	local code
	code="$(curl -sL --compressed --max-time "$TIMEOUT" -w '%{http_code}' \
		-H "User-Agent: $UA" -H "Accept: text/html,application/xhtml+xml,*/*;q=0.8" \
		-H "Accept-Language: en-US,en;q=0.9" \
		-o "$TMPD/page.html" "$1" 2>/dev/null)" || { note_failure "$2" "curl failed/timeout"; return 1; }
	if [ "$code" != "200" ]; then
		note_failure "$2" "HTTP $code"
		return 1
	fi
	"$PY" "$SCRIPT_DIR/_extract.py" <"$TMPD/page.html" >"$TMPD/out.json" 2>"$TMPD/ex.err" \
		|| { note_failure "$2" "extraction failed: $(tail -c 150 "$TMPD/ex.err" | tr '\n' ' ')"; return 1; }
	emit_success "$2" "$TMPD/out.json" || { note_failure "$2" "empty extraction"; return 1; }
}

try_curl() { fetch_and_extract "$URL" curl; }

try_playwright() {
	"$PY" -c "import playwright" 2>/dev/null || { note_failure playwright "playwright not installed for $PY (pip install playwright && playwright install chromium)"; return 1; }
	if ! URL="$URL" UA="$UA" TIMEOUT="$TIMEOUT" "$PY" - >"$TMPD/page.html" 2>"$TMPD/pw.err" <<'PY'
import os, sys
from playwright.sync_api import sync_playwright
url, ua = os.environ["URL"], os.environ["UA"]
timeout_ms = int(float(os.environ["TIMEOUT"]) * 1000)
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(user_agent=ua, viewport={"width": 1280, "height": 900})
    page.goto(url, timeout=timeout_ms, wait_until="domcontentloaded")
    page.wait_for_timeout(1500)  # let SPA content settle
    sys.stdout.write(page.content())
    browser.close()
PY
	then
		note_failure playwright "$(tail -c 200 "$TMPD/pw.err" | tr '\n' ' ')"
		return 1
	fi
	"$PY" "$SCRIPT_DIR/_extract.py" <"$TMPD/page.html" >"$TMPD/out.json" 2>"$TMPD/ex.err" \
		|| { note_failure playwright "extraction failed: $(tail -c 150 "$TMPD/ex.err" | tr '\n' ' ')"; return 1; }
	emit_success playwright "$TMPD/out.json" || { note_failure playwright "empty extraction"; return 1; }
}

try_camoufox() {
	command -v "$CAMOUFOX_PYTHON" >/dev/null 2>&1 || { note_failure camoufox "no python at $CAMOUFOX_PYTHON"; return 1; }
	"$CAMOUFOX_PYTHON" -c "import camoufox" 2>/dev/null \
		|| { note_failure camoufox "camoufox not installed for $CAMOUFOX_PYTHON (see README: optional extras)"; return 1; }
	if ! URL="$URL" TIMEOUT="$TIMEOUT" "$CAMOUFOX_PYTHON" - >"$TMPD/page.html" 2>"$TMPD/cf.err" <<'PY'
import os, sys
from camoufox.sync_api import Camoufox
url = os.environ["URL"]
timeout_ms = int(float(os.environ["TIMEOUT"]) * 1000)
with Camoufox(headless=True, geoip=True) as browser:
    page = browser.new_page()
    page.goto(url, timeout=timeout_ms, wait_until="domcontentloaded")
    page.wait_for_timeout(2000)  # let JS challenges/SPA content settle
    sys.stdout.write(page.content())
PY
	then
		note_failure camoufox "$(tail -c 200 "$TMPD/cf.err" | tr '\n' ' ')"
		return 1
	fi
	"$PY" "$SCRIPT_DIR/_extract.py" <"$TMPD/page.html" >"$TMPD/out.json" 2>"$TMPD/ex.err" \
		|| { note_failure camoufox "extraction failed: $(tail -c 150 "$TMPD/ex.err" | tr '\n' ' ')"; return 1; }
	emit_success camoufox "$TMPD/out.json" || { note_failure camoufox "empty extraction"; return 1; }
}

try_wayback() {
	local code snap
	code="$(curl -s --max-time "$TIMEOUT" -w '%{http_code}' -o "$TMPD/wb.json" \
		--get --data-urlencode "url=$URL" \
		"https://archive.org/wayback/available" 2>/dev/null)" || code="000"
	if [ "$code" != "200" ]; then
		note_failure wayback "availability API HTTP $code (429 = rate-limited, retry later)"
		return 1
	fi
	snap="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
s = (d.get("archived_snapshots") or {}).get("closest") or {}
print(s.get("url", "") if s.get("available") else "")' "$TMPD/wb.json" 2>/dev/null)" || snap=""
	if [ -z "$snap" ]; then
		note_failure wayback "no snapshot of this URL"
		return 1
	fi
	fetch_and_extract "$snap" wayback
}

IFS=',' read -ra LADDER <<<"$METHODS"
for rung in "${LADDER[@]}"; do
	case "$rung" in
	exa) try_exa && exit 0 ;;
	kagi) try_kagi && exit 0 ;;
	curl) try_curl && exit 0 ;;
	playwright) try_playwright && exit 0 ;;
	camoufox) try_camoufox && exit 0 ;;
	wayback) try_wayback && exit 0 ;;
	*) echo "Unknown method: $rung" >&2; exit 2 ;;
	esac
	echo "fetch-page: rung '$rung' failed, falling back" >&2
done

URL="$URL" ATT="$ATTEMPTS" python3 -c '
import json, os
print(json.dumps({"url": os.environ["URL"], "error": "all methods failed",
                  "attempts": json.loads(os.environ["ATT"])}))'
exit 1
