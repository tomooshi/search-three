---
name: web-research
description: "Multi-source web research coordinating three engines with different retrieval paradigms: Kagi (lexical, commercial-quality), Marginalia (anti-SEO indie/old web, free), and Exa (neural/semantic). meta-search.sh fans out in parallel, dedupes by normalized URL, and flags URLs that several engines found independently — the strongest relevance signal available. fetch-page.sh turns any URL into markdown via a fallback ladder (Exa → Kagi → curl → Playwright → Camoufox → Wayback) for bot-walled, JS-heavy, or dead pages. Use for open-ended research: 'research X', 'deep dive on', 'find the best sources about', 'thorough search', source surveys, contested claims, topic landscapes — and whenever a page fetch fails or a site blocks scraping. For a single quick lookup use kagi-search, exa-search, or marginalia-search directly."
---

# Web Research (Kagi + Marginalia + Exa coordinator)

This skill sits **above** three engine skills and coordinates them. The engine skills are **sibling folders** of this one (`../kagi-search`, `../marginalia-search`, `../exa-search`); all `./scripts/...` paths below are relative to this skill's own directory.

**First run:** `./scripts/doctor.sh` checks tools, API keys, and optional extras (no network calls; add `--live` for one real query per engine). If a key is missing, the fix is in that engine's SKILL.md → Setup.

- **kagi-search** (`../kagi-search/`) — lexical + quality re-ranking (hybrid index: own + upstream commercial), $0.012/search + $0.004/extract, operator precision (site:/filetype:), news workflows, X/Twitter extraction.
- **marginalia-search** (`../marginalia-search/`) — lexical anti-SEO, fully own index, free, **1000 queries/day hard limit**, snippets only, indie/old-web coverage nothing else has.
- **exa-search** (`../exa-search/`) — **neural/semantic** (custom-trained embeddings over Exa's own crawl), $0.007/search, $0.001/contents (cheapest extraction), find-similar (URL → semantic neighbors), category search (papers/companies/people/github). Free $10/mo credits.

Three engines = three retrieval mechanisms. When lexical, anti-SEO-lexical, AND neural retrieval independently return the same URL, that is the strongest relevance vote this stack produces (verified: `-e all` on a test query yielded a triple-agreement hit and doubled the overlap count vs two engines).

**Read the engine skill before using engine-specific features** (Kagi lens/filters/workflows, Marginalia custom filters, operator quirks). This skill only covers coordination.

## The one new primitive: fan-out with overlap detection

```bash
./scripts/meta-search.sh "query"              # kagi+marginalia (default), merged
./scripts/meta-search.sh -e all "query"       # + exa — three-paradigm corroboration
./scripts/meta-search.sh -e kagi,exa "query"  # any subset
./scripts/meta-search.sh -c 20 "query"        # results per engine
./scripts/meta-search.sh -w news "query"      # kagi workflow (kagi side only)
```

Cost: default **$0.012 + 1 Marginalia quota**; `-e all` adds **$0.007** (usually covered by Exa's free monthly credits). Use `-e all` for claim verification and high-stakes research; default for routine breadth. Exa results carry `published` dates and (with kagi absent) 500-char text snippets. The Marginalia quota line passes through on stderr.

Output is one JSON object:

```json
{
  "query": "...",
  "engines": {"kagi": "ok", "marginalia": "ok"},
  "overlap": 1,
  "results": [
    {"url": "...", "title": "...", "snippet": "...",
     "sources": ["kagi", "marginalia"],
     "rank": {"kagi": 18, "marginalia": 3},
     "kagi_type": "search", "marginalia_quality": 3.05}
  ]
}
```

- **`sources` with both engines = strong relevance signal.** A commercial index and an anti-SEO indie index agreed independently. These sort first. In testing, an overlap hit ranked #18 on Kagi but #3 on Marginalia — the fan-out surfaced a page Kagi alone would have buried.
- URLs are normalized before dedupe (scheme/`www.`/trailing-slash/percent-encoding differences collapse). Snippets are HTML-stripped; the longer snippet wins.
- One engine failing is non-fatal: `engines` reports `"error: ..."` and you get the other's results. Exit 1 only when **all** engines fail.
- Kagi's `related_search` group is dropped (relative URLs, not results). Other groups keep their name in `kagi_type`.

## Extraction with fallback: fetch-page.sh

Kagi extract is the best extraction path but not the only one — it fails on some bot-walled, dead, or unindexed pages. `fetch-page.sh` walks an escalation ladder automatically and reports which rung succeeded plus why earlier rungs failed:

```bash
./scripts/fetch-page.sh URL                      # ladder: exa → kagi → curl → playwright → camoufox → wayback
./scripts/fetch-page.sh -m curl,playwright URL   # skip kagi (save $0.004 on easy pages)
./scripts/fetch-page.sh -m wayback URL           # straight to archive (known-dead page)
./scripts/fetch-page.sh -t 40 URL                # per-rung timeout seconds (default 25)
```

| Rung | Cost | Handles | Doesn't handle |
|---|---|---|---|
| `exa` | **$0.001** | most pages via Exa's crawl cache (fast; succeeded on seirdy.one where Kagi failed) | X/Twitter (auto-skipped), cache can be stale, thin-content pages |
| `kagi` | $0.004 | most pages, X/Twitter, best markdown quality | some bot walls, dead pages |
| `curl` | free | static HTML, no-JS pages | SPAs, bot walls (403/shell pages) |
| `playwright` | free, ~3-5s | JS-rendered SPAs, mild bot walls (verified: Reddit) | Cloudflare turnstile, logins |
| `camoufox` | free, ~10s, ~200MB RAM | fingerprint-checked walls that block plain headless browsers (anti-detect Firefox, geoip, uBO) | logins, CAPTCHAs that need a human |
| `wayback` | free | dead pages, hard walls (if archived) | never-archived URLs (stale content); API itself 429s under load |

Output: `{"url", "method", "title", "markdown", "attempts": {rung: error, ...}}` — exit 1 with an `attempts` breakdown if every rung fails. The local rungs use `scripts/_extract.py` (bs4-based, preserves headings/links/lists/code); quality is below Kagi's but serviceable.

Verified live 2026-09-01: Reddit's shell page fails the `curl` rung (“empty extraction”) and succeeds on `playwright` with real content; Kagi rung returns full 22K-char posts; hard 404s produce clean per-rung diagnostics.

Gotchas:

- **Soft-404s pass the ladder.** A parked/redirected domain returns HTTP 200 with junk (verified: geocities.com → parking page, 118 chars). Sanity-check `markdown` length and content against what you expected — a suspiciously short result from a `curl` rung on an old URL usually means the real page is on `wayback`.
- **archive.org's availability API rate-limits aggressively** (HTTP 429, reported in `attempts`). Retry later or fetch `https://web.archive.org/web/<url>` manually.
- **The free rungs are optional extras.** `curl`/`playwright`/`camoufox`/`wayback` need `beautifulsoup4`; `playwright` also needs `pip install playwright && playwright install chromium`; `camoufox` needs the `camoufox` package plus `camoufox fetch`. A missing extra just fails that rung with a clear message in `attempts` and the ladder moves on. `FETCH_PYTHON` picks the python used for bs4/playwright (default `python3`); `CAMOUFOX_PYTHON` picks the one for camoufox (default `~/.venvs/camoufox/bin/python` if it exists, else `FETCH_PYTHON`). Run `./scripts/doctor.sh` to see which rungs are available.
- Playwright is plain headless Chromium with a desktop UA — *not* anti-detect; Camoufox is the anti-detect escalation and sits right after it in the ladder. Keep Camoufox in a dedicated venv (e.g. `~/.venvs/camoufox`) — system-Python upgrades can silently remove it. If the rung reports a version/install error, re-run `<that-python> -m camoufox fetch`.
- For logged-in views or bulk session work, Camoufox-the-rung isn't enough — use the session-hybrid pattern (Camoufox establishes cookies, `curl_cffi` bulk-pulls) described in the kagi-search skill's X/Twitter section.
- Ladder order is cost-aware, not speed-aware: the paid APIs (`exa` $0.001, then `kagi` $0.004) go first because they beat 5s of Chromium, and `camoufox` after `playwright` because 10s + 200MB should only fire when the cheap browser failed. In a free-only loop use `-m curl,playwright,camoufox,wayback`.

Verified live 2026-09-01: `-m camoufox` extracts fine, and `-m curl,camoufox` on Reddit falls through curl (“empty extraction”) into a successful Camoufox render.

## Routing: fan out or go direct?

Fan-out is not the default. It spends multiple budgets, so route first. The first question is **what shape is the query?** — keyword-shaped (names, exact terms, operators) → lexical engines; description-shaped ("essays arguing…", "tools similar to…") → Exa; both → fan-out.

| Situation | Route |
|---|---|
| Single fact, quick lookup ("when was X", "who is Y") | **Kagi direct**, `search-v1.sh "Q" 2` — extraction answers it in one call |
| Known URL to read | **`fetch-page.sh URL`** (exa rung $0.001 → kagi $0.004 → free rungs) — never search for what you already have |
| "More sources like this one" (have a known-good URL) | **Exa `find-similar.sh URL`** — skip search entirely; nothing else does this |
| Conceptual / descriptive query ("blog posts where practitioners argue X") | **Exa direct** (`../exa-search/scripts/search.sh`) — neural retrieval's home turf; keyword engines mangle these |
| Papers, companies, people, GitHub repos, PDFs as a class | **Exa `-c` category** (`"research paper"`, `company`, `github`, `pdf`…) |
| Exact string / identifier / operator-scoped (`site:`, `filetype:`) | **Kagi direct** (Exa `-t keyword` is a weaker second) |
| News / current events / images / videos / X | **Kagi direct** (only engine with these workflows + tweet extraction) |
| Indie/old-web/blog discovery, `year<` filtering, SEO-spam-prone topics | **Marginalia direct** (free; the others under-index this) |
| Open-ended research, topic landscape, "find the best sources" | **Fan-out** (default 2-engine; `-e all` if the query is even partly conceptual) |
| Contested claim, need independent corroboration | **Fan-out `-e all`** — three retrieval paradigms agreeing is the strongest vote we have |
| Tight loop (query expansion, evals, many candidate queries) | **Marginalia direct** (free) for candidates; one fan-out on the winner. Exa's $10/mo credits make it the second-cheapest loop engine |

## Workflow recipes

### Breadth-then-depth (default research pattern)

0. If the question is *conceptual* ("essays arguing…", "projects similar to…"), phrase it descriptively and consider `-e all` — neural retrieval shines exactly where keyword phrasing fails. For "more like this known-good source", skip search entirely: `../exa-search/scripts/find-similar.sh URL`.
1. `meta-search.sh -c 15 "topic"` — one fan-out for breadth.
2. Triage the merged list: overlap hits first, then judge titles/snippets. Marginalia's `marginalia_quality` is **lower = better**; its `resultsFromDomain` (via the engine skill) distinguishes personal sites from megasites.
3. Extract only the winners — cheapest first: `fetch-page.sh URL` (exa rung, $0.001, falls back automatically) or `../exa-search/scripts/contents.sh URL1 URL2 …` for bulk; Kagi extract ($0.004) for X/Twitter or when Exa's cache is stale (`-l` livecrawl first if freshness matters).
4. Total: ~$0.012 + $0.001×N — versus $0.052 for a naive Kagi search with extract=10.

### Claim verification

1. `meta-search.sh -e all` with the claim phrased neutrally (not as a leading question). Phrase it descriptively enough that the neural engine has something to match.
2. Check `overlap` — a `k+m+e` hit (all three paradigms) is the highest-confidence source; two-engine hits next. Weight by *how different* the agreeing mechanisms are.
3. Extract 3–5 pages spanning **all** source pools via `fetch-page.sh` (don't extract only Kagi hits; Marginalia surfaces non-SEO'd primary sources, Exa surfaces semantically-on-point pages keyword ranking buried).
4. For evidence-grade claims, add `../exa-search/scripts/search.sh -c "research paper" "<claim>"` — the scholarly index is the shortcut to the top of the evidence hierarchy.
5. If the claim is recent, add a `meta-search.sh -w news` pass — Marginalia crawls slowly and Exa's cache can lag, so weigh absence of recent results as "not yet indexed", not "not true".

### Indie deep-dive

1. `../marginalia-search/scripts/search.sh -c 20 -d 1 "topic"` — free, one result per domain maximizes site diversity.
2. Paginate (`-p 2`, `-p 3`) while promising domains keep appearing — still free.
3. **Expand from the best find**: `../exa-search/scripts/find-similar.sh -e <best-url>` — semantic neighbors of a great indie page are usually more great indie pages, and Exa's `-c "personal site"` category is a second indie-discovery axis Marginalia's index doesn't cover.
4. Extract chosen pages via `fetch-page.sh` (exa rung first, $0.001).
5. Optional: build a Marginalia custom filter (`filter.sh`) if this is a recurring beat — server-side, persistent, free to apply.

### Multi-angle survey

For a landscape question, run 2–4 fan-outs with *different phrasings/facets*, not one fan-out with a vague query. Make at least one phrasing description-shaped and run it `-e all` so the neural paradigm contributes. Dedupe across runs by URL (the script only dedupes within a run). URLs recurring **across phrasings** are a second agreement signal, orthogonal to cross-engine overlap. Close with one `find-similar.sh` on the strongest result to catch what no phrasing reached.

## Budget model

Per-pattern cost at a glance:

| Pattern | Kagi $ | Exa $ | Marginalia quota |
|---|---|---|---|
| Quick fact (Kagi direct, extract 2) | $0.020 | 0 | 0 |
| Known URL (fetch-page, exa rung hits) | 0 | $0.001 | 0 |
| Conceptual query (Exa direct) | 0 | $0.007 | 0 |
| Find-similar expansion | 0 | $0.007 | 0 |
| Breadth-then-depth (fan-out + 3 extracts via ladder) | $0.012 | $0.003 | 1 |
| Claim verification (`-e all` + scholarly pass + news pass + 5 extracts) | $0.024 | $0.019 | 2 |
| Indie deep-dive (3 Marginalia pages + find-similar + 3 extracts) | 0 | $0.010 | 3 |
| Multi-angle survey (3 fan-outs, one `-e all`, + find-similar + 5 extracts) | $0.036 | $0.019 | 3 |

Exa's **$10/month free credits ≈ $0.33/day** — every pattern above runs inside that on a normal day, so Exa spend is effectively free until you're doing serious volume. Every script call is logged to a local ledger; `./scripts/search-cost.sh` prints today / month / all-time spend for all three engines. (In pi, the bundled `search-cost` extension also shows a live footer — `⌕ kagi $ · exa $ · marg n/1k` — and a `/search-cost` command.) Marginalia's 1000/day is generous for interactive use but a **hard 503 wall** in loops — batch and dedupe queries before firing.

## Failure fallbacks

- **Marginalia 503 (quota)** — continue with `-e kagi,exa`. Quota resets at UTC midnight. Losing Marginalia costs the indie-web axis; say so if that mattered.
- **Exa 402 (credits exhausted)** — continue with default 2-engine fan-out; extraction falls back to the kagi rung automatically (`fetch-page.sh` skips a failing exa rung). Free credits reset monthly; top-up is optional.
- **Exa contents stale** (`statuses[].source: cached` on a page that changes) — re-run `contents.sh -l URL` (livecrawl) or fall to the kagi rung.
- **Any extract fails on a specific URL** — that's what `fetch-page.sh` is for; it walks exa → kagi → curl → playwright → camoufox → wayback automatically. If you called an engine's extract script directly, re-run through the ladder.
- **Kagi down entirely** — Marginalia + Exa still cover discovery (`-e marginalia,exa`) and Exa contents + free rungs cover extraction; only news workflows and X/Twitter rendering are lost.
- **All engines down** — stop and report; don't silently answer from training data when the user asked for research.
- **Zero overlap** on a fan-out is *normal* for niche queries (small index intersection); it's a missing bonus signal, not a red flag. Zero results across engines usually means the query phrasing is off — try the *other shape* (keyword ↔ descriptive) before concluding absence: a query that fails lexically often succeeds neurally, and vice versa.

## Verified

Fan-out script tested live 2026-09-01: parallel execution, merge, percent-encoding dedupe (`Gemini_(protocol)` ≡ `Gemini_%28protocol%29`), overlap detection, single-engine mode, and graceful stderr passthrough of the Marginalia quota line all confirmed working.
