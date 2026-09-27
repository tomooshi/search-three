---
name: exa-search
description: "Neural/semantic web search via the Exa API (api.exa.ai) — retrieval by meaning (custom-trained embeddings over Exa's own crawl), not keywords. THE engine for conceptual queries ('essays arguing X', 'companies building Y'), similarity expansion (find-similar.sh: give a URL, get semantically similar pages — no Kagi/Marginalia equivalent), scholarly/company/people/github category search, and cheap page extraction (contents.sh, $0.001/page, 4x cheaper than Kagi extract, often succeeds on pages Kagi's crawler can't reach). Use when the query describes what the answer looks like rather than what words it contains, when expanding from a known-good source, or for 'papers about', 'startups similar to', 'personal sites discussing'. Prefer kagi-search for operator-precision (site:/filetype:), news workflows, X/Twitter; marginalia-search for indie/old-web. Requires EXA_API_KEY or ~/.config/exa/api_key. Free tier: $10 credits/month (~1,400 searches)."
---

# Exa Search (neural)

Exa runs its own crawler, its own index (billions of pages), and retrieval by **custom-trained transformer embeddings** — documents are preprocessed into vectors, not keywords, and served from Exa's own vector database. Verified live 2026-09-01/02.

## Setup

Script paths below (`./scripts/...`) are relative to this skill's directory.

Create a key at https://dashboard.exa.ai (free tier: **$10 credits/month** recurring; balance shown there). The scripts read `EXA_API_KEY`, else `~/.config/exa/api_key`:

```bash
mkdir -p ~/.config/exa
printf '%s' 'YOUR_KEY' > ~/.config/exa/api_key
chmod 600 ~/.config/exa/api_key
```

Requires `bash`, `curl`, `python3` (stdlib only).

## The one habit that matters

**Phrase queries as a description of the answer, not keywords.** Neural retrieval matches meaning:

- ✅ "blog posts where practitioners argue against lazy loading images"
- ❌ "lazy loading criticism" (works, but wastes the paradigm)
- For exact-string/entity lookup use `-t keyword` — neural search is fuzzy by design and will "helpfully" generalize your exact match away.

## Usage

```bash
./scripts/search.sh "essays on why personal websites matter"
./scripts/search.sh -c "research paper" -a 2024-01-01 "form validation usability"
./scripts/search.sh -t keyword "MARGINALIA_API_KEY"       # exact match
./scripts/search.sh -d "nngroup.com,baymard.com" "checkout flow research"
./scripts/search.sh -x -n 5 "digital garden essays"       # + full text ($0.001/pg)

./scripts/find-similar.sh https://lawsofux.com/            # semantic neighbors
./scripts/find-similar.sh -e -n 10 https://seirdy.one/     # exclude source domain

./scripts/contents.sh URL1 URL2                            # $0.001/page
./scripts/contents.sh -l URL                               # livecrawl (fresh, not cache)
./scripts/contents.sh -s URL                               # + AI summary
```

Categories (`-c`): `research paper`, `company`, `news`, `personal site`, `github`, `tweet`, `pdf`, `linkedin profile`, `financial report`.

## Response shape

```json
{
  "requestId": "...", "resolvedSearchType": "neural", "searchTime": 340,
  "costDollars": {"total": 0.007, "search": {"neural": 0.007}},
  "results": [{"id": "...", "url": "...", "title": "...",
               "publishedDate": "2026-04-17T...", "author": "...",
               "text": "(only with -x)"}]
}
```

- `costDollars.total` is authoritative per-request cost — the ledger records it directly (no rate table to maintain).
- `/contents` responses include `statuses[]` with `source: cached|livecrawled` and per-URL errors. **Cached is the default** — content can be stale; use `-l` when freshness matters.
- Verified win: `/contents` served seirdy.one (151K chars) from cache where Kagi's live crawler returned "No data from crawlers".

## Pricing (verified from docs.exa.ai/reference/pricing)

| Endpoint | Cost |
|---|---|
| `/search` (auto/neural/keyword/fast) | **$0.007** base, up to 10 results; +$0.001/result above 10 |
| `/search` type=deep | $0.012–0.015 |
| `/findSimilar` | $0.007 (billed as neural search) |
| `/contents` | **$0.001/page** per content type (text/summary each) |
| `/answer` | $0.005 (cited LLM answer — not wrapped here; the agent does its own synthesis) |

Ledger: `${XDG_STATE_HOME:-~/.local/state}/exa/usage.jsonl` (override path with `EXA_LEDGER=/path`, disable with `EXA_LEDGER=off`); `../web-research/scripts/search-cost.sh` summarizes spend for all three engines (in pi, the bundled `search-cost` extension also shows it in the footer). Free credits make ~$0.33/day effectively free — but the ledger still tracks so habits stay honest.

## When Exa vs the others

| Task | Engine |
|---|---|
| Conceptual/descriptive query | **Exa** (this is the paradigm) |
| "More like this URL" | **Exa find-similar** (only option) |
| Scholarly/company/people/repo scoped | **Exa** categories |
| Cheap bulk extraction of known URLs | **Exa contents** ($0.001) → fall back to Kagi extract ($0.004) for X/Twitter or when Exa's cache misses and livecrawl fails |
| Exact match, operators, `site:` precision | **Kagi** (or Exa `-t keyword`, weaker) |
| News/freshness workflows | **Kagi** `-w news` |
| Indie/old web, anti-SEO | **Marginalia** |
| Multi-engine corroboration | **web-research** `../web-research/scripts/meta-search.sh` (Exa is the third engine: `-e all`) |

## Errors

- 401 → key rejected (check `~/.config/exa/api_key`)
- 402 → out of credits (free tier resets monthly; top up at dashboard)
- 429 → rate limit (free tier: 5 QPS)
- `/contents` partial failures come back in `statuses[]` with HTTP 200 — check per-URL.
