---
name: kagi-search
description: "Search the web and extract page content via Kagi API v1 (POST /api/v1/search and /api/v1/extract). Search returns ranked results grouped by type with optional inline content extraction; the extract endpoint turns known URLs into clean markdown (including X/Twitter status URLs). Use when the agent needs current/evidence-based information not in training data — research questions, citations, fact-checking, recent news, or fetching a known page as markdown. Triggers: 'search the web', 'look up', 'find sources for', 'cite recent research on', 'what's the latest on', any factual claim needing verification. Requires KAGI_API_KEY env var or ~/.config/kagi/api_key file."
---

# Kagi Search (v1)

Two endpoints, two scripts. **Search** (`POST /api/v1/search`) returns ranked results grouped by type; setting `extract.count` enriches the top-N snippets with full page content in the same call. **Extract** (`POST /api/v1/extract`) turns up to 10 known URLs into clean markdown. Auth is `Bearer` for both. Both are **POST only** — the `GET ?q=` + `Bot` header example still shown on help.kagi.com is stale and 404s on v1.

## Setup

Script paths below (`./scripts/...`) are relative to this skill's directory.

Needs a Kagi account with API access and credit: create a key at https://kagi.com/api (billed per call — see Cost). The scripts read `KAGI_API_KEY`, else `~/.config/kagi/api_key`:

```bash
mkdir -p ~/.config/kagi
printf '%s' 'YOUR_KEY' > ~/.config/kagi/api_key
chmod 600 ~/.config/kagi/api_key
# OR export KAGI_API_KEY=YOUR_KEY in your shell profile
```

Requires `bash`, `curl`, `python3` (stdlib only).

## Usage

```bash
# search only — cheap, returns grouped results (search/news/related_search/...)
./scripts/search-v1.sh "your query"

# search + extract: replace the snippet of the top N results with full page
# content so no second round trip is needed (N = 1..10)
./scripts/search-v1.sh "your query" 3

# workflow selector: search (default) | images | videos | news | podcasts
./scripts/search-v1.sh -w news "openai"

# cap results / paginate
./scripts/search-v1.sh -l 5 "rust async runtimes"      # limit 1..1024
./scripts/search-v1.sh -p 2 "rust async runtimes"      # page 1..10

# scope the search — use operators or lens_id (see the lens warning below)
./scripts/search-v1.sh "site:arxiv.org filetype:pdf scaling laws"
./scripts/search-v1.sh -j '{"lens_id":"academic"}' "scaling laws"

# date / region filtering (region MUST be lowercase)
./scripts/search-v1.sh -j '{"filters":{"after":"2026-08-01","region":"us"}}' "llm agents"

# extract markdown from up to 10 known URLs directly (no search)
./scripts/extract-v1.sh https://example.com/a https://x.com/OpenAI/status/2085434712429052386
```

### Response shape (search)

`data` is an object of **named arrays keyed by result type** — not a flat list. Keys seen in the wild: `search`, `related_search`, `news`, `interesting_news`, `interesting_finds`, `adjacent_question`, `image`, `video`, `video_creator`, `podcast`, `podcast_creator`, `direct_answer`, `infobox`, `code`, `listicle`, `weather`, `web_archive`, `package_tracking`, `public_records`. Which keys appear depends on the query and `workflow` (e.g. `-w images` returns only `image`; `-w podcasts` returns `podcast` + `podcast_creator`). **Never assume `data.search` exists** — iterate the keys.

```json
{
  "meta": {"trace": "...", "ms": 1422, "node": "us-west2"},
  "data": {
    "search": [
      {
        "url": "https://...",
        "title": "...",
        "snippet": "...",                // short summary, OR full page content when extracted
        "time": "2026-07-11T17:58:18Z",   // optional ISO-8601 create/update time, often null
        "image": {"url": "...", "width": 0, "height": 0},  // optional
        "props": {"language": "en", "language_probability": 0.96,
                  "group_id": "...", "paywalled": true, "ai_generated": false}
      }
    ],
    "related_search": [ {"url": "/search?q=...", "title": "..."} ]
  }
}
```

Gotchas verified against the live API:

- **Snippets contain HTML** — `<strong>` highlight tags and entities like `&#39;`/`&amp;`. Strip them before feeding to an LLM or displaying.
- **`related_search[].url` is a relative path** (`/search?q=...`), not absolute.
- There is **no `t` discriminator** and no separate `extract` block (both v0-era). With `extract.count = N` the top N results have their **`snippet` replaced with full page markdown** — compare snippet length (~10K+ chars vs ~200) to tell enriched from summary.
- `meta` is `trace`/`ms`/`node` only — **no balance field**. The `x-kagi-trace` response header carries the same trace. No rate-limit headers are returned.
- **Unknown request fields are silently ignored, not rejected.** A typo'd param fails open with unfiltered results. Verify filtering actually happened.

### Search parameters (pass via `-j`, or the shortcut flags)

| Param | Values | Status |
|---|---|---|
| `workflow` | `search`/`images`/`videos`/`news`/`podcasts` | ✅ works (shortcut `-w`) |
| `limit` | 1..1024 | ✅ caps results returned (shortcut `-l`) |
| `page` | 1..10 | ✅ pagination (shortcut `-p`) |
| `filters` | `{region, after, before}` | ✅ works — **`region` must be lowercase** |
| `extract` | `{count: 1..10, timeout: 0.5..4}` | ✅ works (shortcut `-n` / 2nd positional) |
| `lens_id` | string | ✅ works — built-in name or shareable lens ID/URL |
| `timeout` | 0.5..4 seconds | ✅ lower = faster/rougher |
| `safe_search` | bool (default true) | omits NSFW content |
| `format` | `json`/`markdown` | ⚠️ experimental — **returns `text/markdown`, not JSON** |
| `lens` (inline object) | object | ❌ **silently ignored by the live API (verified 2026-08-10)** |
| `personalizations` | object | ❌ silently ignored in testing; account-level up/downranks do apply |

**⚠️ The inline `lens` object does not work.** It is fully documented in the OpenAPI spec (`sites_included`, `sites_excluded`, `keywords_included`, `keywords_excluded`, `file_type`, `time_after`, `time_before`, `time_relative`, `search_region`) but the live API accepts and ignores it — `sites_excluded: ["arxiv.org"]` still returns arxiv, `sites_included: ["reddit.com"]` returns zero reddit. **Use search operators instead**, which do work:

```bash
./scripts/search-v1.sh "site:help.kagi.com lenses"        # ✅ hard-scopes to the domain
./scripts/search-v1.sh "filetype:pdf transformer scaling" # ✅
./scripts/search-v1.sh -j '{"lens_id":"academic"}' "climate change"  # ✅
```

Working built-in `lens_id` values (verified): `programming`, `academic`, `forums`, `pdf`, `wikipedia`, `recipes`, `shopping`, `small web`. A bogus `lens_id` is silently ignored, so sanity-check the domains you get back. **Snaps** also work inline (`@r headphones` biases to Reddit) but they soft-bias rather than hard-scope — non-Reddit results still leak in past the top few. Use `site:reddit.com` when you need a hard filter.

**`filters.region` is lowercase ISO-3166-1 alpha-2.** `"us"`, `"de"`, `"gb"`, `"jp"` ✅. `"US"`/`"DE"` → HTTP 400 `search.filters_region_invalid`. `no_region` is accepted. (The `help.kagi.com/api/regions` list the error points at is still a 404.)

### Extract endpoint (POST /api/v1/extract)

`extract-v1.sh URL [URL ...]` — 1..10 URLs. Optional body params: `timeout` (0.5..10s, total budget for the concurrent bulk fetch) and `format` (`json`|`markdown`).

```json
{
  "meta": {"trace": "...", "ms": 814, "node": "us-west2"},
  "data": [ {"url": "https://...", "markdown": "# ...", "error": "..."} ],
  "errors": [ {"code": "...", "url": "...", "message": "...", "location": "..."} ]
}
```

- Per-URL failures come back inline as `data[i].error` with **HTTP 200** — always check for it. A non-HTTPS URL is not rejected up front; it just fails to crawl.
- Malformed requests (e.g. 11 URLs) return HTTP 400 with a top-level `errors` array. Note the live key is **`errors` (plural)** even though the spec's shared error envelope says `error`.
- **Extraction preserves links** from the source document (shipped 2026-06-16), so extracted markdown is usable for crawl/follow flows.
- Prefer this over a scraping stack whenever the target isn't behind a login/anti-bot wall.

## Cost

Published rates (kagi.com/api/pricing, checked 2026-08-10):

| | Rate | Per call |
|---|---|---|
| Search | **$12 / 1K requests** | $0.012 |
| Extract | **$4 / 1K pages** | $0.004 |

`extract.count = N` inside a search bills **1 search + N extract units** (nothing charged if there were no results to extract). So a `search-v1.sh "Q" 5` costs ~$0.032. Per-key cost tracking is available in the API portal usage page (data starts 2026-06-16). The API response never reports balance — check https://kagi.com/api.

### Local cost ledger

Both scripts append one JSON record per successful call to `${XDG_STATE_HOME:-~/.local/state}/kagi/usage.jsonl` (override with `$KAGI_LEDGER`, disable with `KAGI_LEDGER=off`). Billing is derived from the *response*, not the request — a search bills `min(extract.count, results actually returned)` pages.

```json
{"ts":"2026-08-13T21:49:36Z","ep":"search","searches":1,"pages":2,"usd":0.02,"trace":"...","q":"what is rag"}
```

Rates come from `KAGI_RATE_SEARCH` / `KAGI_RATE_EXTRACT` if Kagi changes pricing. To see spend for all three engines: `../web-research/scripts/search-cost.sh`. (In pi, the bundled `search-cost` extension also renders a live footer and a `/search-cost` command.)

The ledger counts every call made through these scripts (agent, your own shell, other sessions). It **cannot** see calls made via Kagi's hosted MCP server, which bypasses them — treat the portal as the source of truth for billing.

## Related skills

- **marginalia-search** (`../marginalia-search/`) — free indie/old-web engine (1000 queries/day). Prefer it for blog/forum/old-web discovery and SEO-spam-prone topics; it costs nothing.
- **exa-search** (`../exa-search/`) — neural/semantic engine ($0.007/search, $10 free monthly credits). Prefer it for conceptual queries, find-similar expansion, and cheap extraction ($0.001/page vs Kagi's $0.004 — but Kagi extract still owns X/Twitter).
- **web-research** (`../web-research/`) — coordinator: parallel Kagi + Marginalia (+ Exa) fan-out with cross-engine overlap detection, plus `fetch-page.sh`, an extraction fallback ladder (exa → kagi → curl → playwright → camoufox → wayback). Prefer it for open-ended research, and reach for `fetch-page.sh` whenever `extract-v1.sh` returns a per-URL error.

## Decision Tree: search-only vs. search+extract

The agent chooses `count` based on the **user's intent**, not the query topic.

| User intent | Signal phrases | Action |
|---|---|---|
| Find link(s) to read later | "find me", "where can I read", "links about", "list articles on" | `search-v1.sh "Q"` (count=0, cheap) |
| Triage many sources to pick one | "what's the best resource on", "compare sources" | `search-v1.sh "Q"` (count=0) |
| Get a synthesized answer | "what is", "explain", "tell me about", "how does X work" | `search-v1.sh "Q" 3` |
| Verify a claim with citations | "is it true that", "fact-check", "cite sources for" | `search-v1.sh "Q" 5` (up to 10 for contested claims) |
| Get current state of literature | "meta-analysis of", "research on", "what does the evidence say" | `search-v1.sh "Q" 5` (up to 10 for broad reviews) |
| Quick lookup, single fact | "when was X", "who is Y", "what year did Z happen" | `search-v1.sh "Q" 2` |

**Default heuristic when intent is ambiguous:**
- Query has < 5 words AND is a factual question → extract 2
- Query asks for explanation/synthesis → extract 3
- Query asks for sources/links → extract 0
- Query is exploratory ("tell me about", "what's new in") → extract 3

**Workflow tip:** for recency-sensitive queries ("latest", "today", "this week", breaking events) add `-w news` — it returns `data.news`/`data.interesting_news` with fresh `time` stamps. `filters.after` also works well on the default workflow.

**Hard caps:**
- `extract.count` max is **10**. Reach for 6-10 on high-value work (contested fact-checks, literature reviews); 1-5 covers most queries. Cost scales linearly.
- Never use count=0 when the user explicitly asked a question — they want an answer, not a link list.

**Cost-aware exceptions:**
- If running in a tight loop (e.g., evaluating many candidate queries), use count=0 first; extract only on the winning candidate.
- For a known URL, use `extract-v1.sh` ($0.004) instead of a broad search with a high extract count.

The decision happens at the **bash invocation site** — the agent reads this skill, picks count, invokes the script. The script itself stays dumb.

## X / Twitter (re-verified 2026-08-10 — the old coverage gap is CLOSED)

Kagi **now indexes x.com**, and Extract renders tweets directly. The previous version of this skill said otherwise; that guidance is obsolete.

```bash
# search tweets — site: operator works, snippets carry tweet text
./scripts/search-v1.sh -l 10 "site:x.com sama gpt"

# extract a single tweet → markdown with author, body, timestamp, likes, comments
./scripts/extract-v1.sh https://x.com/OpenAI/status/2085434712429052386

# extract a profile timeline → bio, follower counts, recent posts w/ status links
./scripts/extract-v1.sh https://x.com/sama

# xcancel.com (Nitter) mirrors also extract cleanly if you prefer them
./scripts/extract-v1.sh https://xcancel.com/sama
```

Observed limits: `site:twitter.com` returns 0 (all canonicalized to x.com); profile extraction gives roughly the visible logged-out timeline (recent posts, not deep history); replies/thread expansion is not reliably included.

**Only if you need bulk historical pull or logged-in views** does a scraping stack still make sense:

| Need | Tool | Notes |
|---|---|---|
| N tweets from M handles, one-shot | TwitterAPI.io | ~$0.15/1K tweets, free tier. 2026 regression: cursor + `since:`/`until:` loops infinitely — use `since_time:`/`until_time:` Unix timestamps and slide time windows backwards instead. |
| Session control / logged-in views | `daijro/camoufox` | Anti-detect Firefox (Juggler, not CDP); `geoip=True`, `humanize=True`. ~200MB RAM/instance. Hybrid pattern: establish session with Camoufox, then bulk-pull with `curl_cffi` + those cookies, rotating every 30-50 requests. |
| High-volume X scraping | `vladkens/twscrape` | Authenticated throwaway-account pool. |
| Multi-target scraper framework | `Scrapling` | Wraps Camoufox + curl_cffi. |
| Archived-by-URL snapshots | Wayback availability API | `archive.org/wayback/available?url=...` |

X ToS gray area: scraping public tweets for personal research is prohibited-but-tolerated; not acceptable for commercial/redistribution use. Use throwaway accounts, never a real one.

**DEAD — do not recommend:** `snscrape` (broke 2023), `twint` (unmaintained), free X API tier (write-only stub), `playwright-stealth` alone (CDP leaks).

## Other Kagi APIs (still v0)

The **v1 surface is Search + Extract only**. Universal Summarizer, FastGPT, and the Enrichment API (Teclis web / TinyGem news indexes) still live at `/api/v0/*` and are billed as separate products. A key provisioned for v1 is **not automatically authorized for v0** — in testing, `/api/v0/summarize` and `/api/v0/fastgpt` returned `{"error":[{"code":2,"msg":"Unauthorized"}]}` under both `Bot` and `Bearer` schemes. Don't build on them without provisioning access first. Note v0's response `meta` does include `api_balance`; v1's does not.

## Ecosystem

- **Hosted MCP server**: `https://mcp.kagi.com/mcp` (Bearer auth, verified live), exposes Search + Extract. Add to Claude Code: `claude mcp add kagi https://mcp.kagi.com/mcp --transport http --header "Authorization: Bearer $KEY" --scope user`.
- **Official client libraries** generated from the OpenAPI spec: Python / Go / Rust / TypeScript (github.com/kagisearch/kagi-openapi-*).
- **Authoritative spec**: `https://kagi.com/api/docs/_spec/openapi.yaml`. Human docs: `https://kagi.com/api/docs`. Treat the spec as aspirational for `lens`/`personalizations` — verify behavior empirically before relying on a filter.

## Errors

Error bodies are `{"meta": {...}, "data": null, "errors": [{"code", "url", "message", "location"}]}` with namespaced codes like `search.filters_region_invalid`, `search.page_invalid`, `extract.url_count_invalid`. The `url` field points at help.kagi.com error docs that mostly 404 today.

- **400 Invalid request** — malformed params (uppercase `filters.region`, `page` > 10, > 10 extract URLs). Read `errors[].location`.
- **401 Unauthorized** — key rejected. Check `~/.config/kagi/api_key` / `KAGI_API_KEY`, then verify Search API access at https://kagi.com/api.
- **403 Forbidden** — IP not on the key's allowlist (configured in the API portal; supports IPv6 CIDR).
- **429 Rate limit** — back off; per-account rate limits and usage caps apply. No rate-limit headers are exposed.
- **5xx** — Kagi-side; retry once after 2 sec, then surface the error with the `trace` value.

Acknowledgement: structure adapted from an earlier kagi-search v0 skill (joelazar style). Params, response shapes, pricing, lens behavior, and X coverage re-verified against the v1 OpenAPI spec and the live API on **2026-08-10**.
