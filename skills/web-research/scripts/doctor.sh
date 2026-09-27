#!/bin/bash
# scripts/doctor.sh — check that the search-three skills are ready to use.
#
# Checks required tools, API keys for each engine, and the optional
# extraction extras used by fetch-page.sh. Makes NO network calls unless
# --live is given.
#
# Usage:
#   doctor.sh           # offline checks only (free)
#   doctor.sh --live    # + one real query per configured engine
#                       #   (kagi ~$0.012, exa ~$0.007, marginalia 1 quota)
#
# Exit status: 0 if every engine has a key and required tools exist, else 1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SEARCH_SKILLS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PY="${FETCH_PYTHON:-python3}"
LIVE=""
[ "${1:-}" = "--live" ] && LIVE=1

FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

echo "Required tools"
for t in bash curl python3; do
	if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t not found"; fi
done

echo "Skills (in $SKILLS_ROOT)"
for s in web-research kagi-search exa-search marginalia-search; do
	if [ -f "$SKILLS_ROOT/$s/SKILL.md" ]; then ok "$s"; else bad "$s missing — keep all four skill folders side by side (or set SEARCH_SKILLS_DIR)"; fi
done

# key_status ENV_VAR CONFIG_DIR
key_status() {
	local var="$1" dir="$2"
	if [ -n "${!var:-}" ]; then
		echo "env"
	elif [ -s "$HOME/.config/$dir/api_key" ]; then
		echo "file"
	else
		echo "none"
	fi
}

echo "API keys"
k="$(key_status KAGI_API_KEY kagi)"
case "$k" in
none) bad "kagi: no KAGI_API_KEY and no ~/.config/kagi/api_key  → https://kagi.com/api" ;;
*) ok "kagi ($k)" ;;
esac
e="$(key_status EXA_API_KEY exa)"
case "$e" in
none) bad "exa: no EXA_API_KEY and no ~/.config/exa/api_key  → https://dashboard.exa.ai" ;;
*) ok "exa ($e)" ;;
esac
m="$(key_status MARGINALIA_API_KEY marginalia)"
case "$m" in
none) warn "marginalia: no key — falling back to the shared, heavily rate-limited 'public' key  → https://about.marginalia-search.com/article/api/" ;;
*) ok "marginalia ($m)" ;;
esac

echo "Optional fetch-page.sh extras (free fallback rungs)"
if "$PY" -c "import bs4" 2>/dev/null; then
	ok "beautifulsoup4 ($PY) — enables curl / playwright / camoufox / wayback rungs"
else
	warn "beautifulsoup4 missing for $PY — local rungs disabled (pip install beautifulsoup4, or set FETCH_PYTHON)"
fi
if "$PY" -c "import playwright" 2>/dev/null; then
	ok "playwright ($PY)"
else
	warn "playwright missing — JS-rendered page rung disabled (pip install playwright && playwright install chromium)"
fi
CF="${CAMOUFOX_PYTHON:-}"
if [ -z "$CF" ]; then
	if [ -x "$HOME/.venvs/camoufox/bin/python" ]; then CF="$HOME/.venvs/camoufox/bin/python"; else CF="$PY"; fi
fi
if "$CF" -c "import camoufox" 2>/dev/null; then
	ok "camoufox ($CF)"
else
	warn "camoufox missing — anti-detect rung disabled (optional; see README)"
fi

if [ -n "$LIVE" ]; then
	echo "Live checks"
	if [ "$k" != "none" ]; then
		if bash "$SKILLS_ROOT/kagi-search/scripts/search-v1.sh" -l 1 "kagi search api" >/dev/null 2>/tmp/doctor-kagi.$$; then
			ok "kagi search"
		else bad "kagi search: $(head -c 200 /tmp/doctor-kagi.$$)"; fi
	fi
	if [ "$e" != "none" ]; then
		if bash "$SKILLS_ROOT/exa-search/scripts/search.sh" -n 1 "exa neural search api" >/dev/null 2>/tmp/doctor-exa.$$; then
			ok "exa search"
		else bad "exa search: $(head -c 200 /tmp/doctor-exa.$$)"; fi
	fi
	if bash "$SKILLS_ROOT/marginalia-search/scripts/search.sh" -c 1 "linear b" >/dev/null 2>/tmp/doctor-marg.$$; then
		ok "marginalia search ($(grep -o 'quota: .*' /tmp/doctor-marg.$$ || echo 'no ledger'))"
	else bad "marginalia search: $(grep -v quota /tmp/doctor-marg.$$ | head -c 200)"; fi
	rm -f /tmp/doctor-*.$$
fi

echo
if [ "$FAIL" = 0 ]; then
	echo "Ready."
else
	echo "Not ready — fix the ✗ items above."
fi
exit "$FAIL"
