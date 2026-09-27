#!/bin/bash
set -uo pipefail

# scripts/meta-search.sh — parallel fan-out to Kagi + Marginalia (+ Exa), merged.
#
# Runs engines concurrently, normalizes URLs, dedupes, and flags results found
# by MULTIPLE engines. With -e all the corroboration signal spans three
# retrieval paradigms (lexical, anti-SEO lexical, neural) — agreement across
# mechanisms is the strongest relevance vote this stack can produce.
#
# Cost: kagi $0.012 + marginalia 1 quota (default); + exa $0.007 with -e all.
# Tolerates engines failing — you get whatever succeeded.
#
# Usage:
#   meta-search.sh [options] "query"
#
# Options:
#   -c COUNT    results per engine (default 10)
#   -e ENGINES  comma list or alias: both (kagi,marginalia — default) | all
#               (kagi,marginalia,exa) | any subset e.g. kagi,exa | single engine
#   -w WORKFLOW kagi workflow: search|news|images|videos|podcasts (kagi side only)
#
# Output (JSON):
#   {
#     "query": "...",
#     "engines": {"kagi": "ok"|"error: ...", "marginalia": "ok"|"error: ..."},
#     "overlap": 2,                     // count of URLs both engines returned
#     "results": [
#       {"url", "title", "snippet",
#        "sources": ["kagi","marginalia"],   // both-engine hits sort first
#        "rank": {"kagi": 1, "marginalia": 3},
#        "marginalia_quality": 3.05,         // lower = better (if present)
#        "kagi_type": "search"}              // kagi result-group key (if present)
#     ]
#   }

# Engine skills are siblings of this skill (skills/<name>/scripts). Override
# with SEARCH_SKILLS_DIR if you installed them somewhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SEARCH_SKILLS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KAGI_SCRIPTS="$SKILLS_ROOT/kagi-search/scripts"
MARG_SCRIPTS="$SKILLS_ROOT/marginalia-search/scripts"
EXA_SCRIPTS="$SKILLS_ROOT/exa-search/scripts"

COUNT=10
ENGINE="both"
WORKFLOW=""

while getopts ":c:e:w:" opt; do
	case "$opt" in
	c) COUNT="$OPTARG" ;;
	e) ENGINE="$OPTARG" ;;
	w) WORKFLOW="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

QUERY="${1:?Usage: meta-search.sh [options] \"query\"}"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

case "$ENGINE" in
both) ENGINE="kagi,marginalia" ;;
all) ENGINE="kagi,marginalia,exa" ;;
esac

wants() { case ",$ENGINE," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

[ -n "$ENGINE" ] || { echo "-e needs at least one engine" >&2; exit 2; }
IFS=',' read -ra _REQ <<<"$ENGINE"
for e in "${_REQ[@]}"; do
	case "$e" in
	kagi | marginalia | exa) ;;
	*) echo "Unknown engine: $e (use kagi, marginalia, exa, both, all)" >&2; exit 2 ;;
	esac
done

PIDS=()
if wants kagi; then
	KARGS=(-l "$COUNT")
	[ -n "$WORKFLOW" ] && KARGS+=(-w "$WORKFLOW")
	bash "$KAGI_SCRIPTS/search-v1.sh" "${KARGS[@]}" "$QUERY" \
		>"$TMPD/kagi.json" 2>"$TMPD/kagi.err" &
	PIDS+=($!)
fi
if wants marginalia; then
	bash "$MARG_SCRIPTS/search.sh" -c "$COUNT" "$QUERY" \
		>"$TMPD/marg.json" 2>"$TMPD/marg.err" &
	PIDS+=($!)
fi
if wants exa; then
	bash "$EXA_SCRIPTS/search.sh" -n "$COUNT" "$QUERY" \
		>"$TMPD/exa.json" 2>"$TMPD/exa.err" &
	PIDS+=($!)
fi
[ "${#PIDS[@]}" -gt 0 ] && { wait "${PIDS[@]}" 2>/dev/null || true; }

# Surface the marginalia quota line (its stderr) so the agent sees it.
grep -h 'marginalia quota' "$TMPD/marg.err" 2>/dev/null >&2 || true

QUERY="$QUERY" TMPD="$TMPD" python3 <<'PY'
import html, json, os, re, sys
from urllib.parse import unquote, urlsplit

tmpd = os.environ["TMPD"]

def norm(url):
    """Normalize a URL for cross-engine dedupe."""
    s = urlsplit(url.strip())
    host = s.netloc.lower()
    host = host[4:] if host.startswith("www.") else host
    path = unquote(s.path).rstrip("/")
    q = f"?{unquote(s.query)}" if s.query else ""
    return f"{host}{path}{q}"

def strip_html(text):
    return html.unescape(re.sub(r"<[^>]+>", "", text or ""))

def load(name):
    path = os.path.join(tmpd, f"{name}.json")
    errp = os.path.join(tmpd, f"{name}.err")
    if not os.path.exists(path) and not os.path.exists(errp):
        return None, "skipped"
    try:
        with open(path) as f:
            raw = f.read()
        if not raw.strip():
            raise ValueError("empty response")
        return json.loads(raw), "ok"
    except Exception as e:
        err = ""
        try:
            with open(errp) as f:
                err = " ".join(
                    l.strip() for l in f if "marginalia quota" not in l
                ).strip()
        except OSError:
            pass
        return None, f"error: {err or e}"

merged = {}   # norm_url -> record
order = []    # insertion order of norm_urls

def add(url, title, snippet, source, rank, **extra):
    key = norm(url)
    if key not in merged:
        merged[key] = {
            "url": url, "title": title, "snippet": snippet,
            "sources": [], "rank": {},
        }
        order.append(key)
    rec = merged[key]
    if source not in rec["sources"]:
        rec["sources"].append(source)
        rec["rank"][source] = rank
    # Prefer the longer snippet
    if snippet and len(snippet) > len(rec["snippet"] or ""):
        rec["snippet"] = snippet
    for k, v in extra.items():
        rec.setdefault(k, v)

engines = {}

kagi, status = load("kagi")
if status != "skipped":
    engines["kagi"] = status
if kagi:
    rank = 0
    for group, items in (kagi.get("data") or {}).items():
        if group == "related_search":  # relative URLs, not results
            continue
        if not isinstance(items, list):
            continue
        for item in items:
            url = item.get("url")
            if not url or not url.startswith("http"):
                continue
            rank += 1
            add(url, strip_html(item.get("title")),
                strip_html(item.get("snippet")),
                "kagi", rank, kagi_type=group)

marg, status = load("marg")
if status != "skipped":
    engines["marginalia"] = status
if marg:
    for i, item in enumerate(marg.get("results") or [], 1):
        add(item["url"], item.get("title"), item.get("description"),
            "marginalia", i, marginalia_quality=item.get("quality"))

exa, status = load("exa")
if status != "skipped":
    engines["exa"] = status
if exa:
    for i, item in enumerate(exa.get("results") or [], 1):
        add(item["url"], item.get("title") or "",
            (item.get("text") or "")[:500],
            "exa", i, published=item.get("publishedDate"))

# Sort: both-engine hits first, then by best rank across engines.
def sort_key(key):
    rec = merged[key]
    return (-len(rec["sources"]), min(rec["rank"].values()))

results = [merged[k] for k in sorted(order, key=sort_key)]
overlap = sum(1 for r in results if len(r["sources"]) > 1)

print(json.dumps({
    "query": os.environ["QUERY"],
    "engines": engines,
    "overlap": overlap,
    "results": results,
}))

# Fail only if EVERY engine errored.
if engines and all(v.startswith("error") for v in engines.values()):
    sys.exit(1)
PY
