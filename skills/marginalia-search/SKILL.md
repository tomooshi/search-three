---
name: marginalia-search
description: "Search the non-commercial, indie, and old web via the Marginalia Search API (GET api2.marginalia-search.com/search, API-Key header). Surfaces personal blogs, forums, academic pages, retro/niche sites, and text-heavy low-javascript pages that mainstream engines bury under SEO spam. FREE (1000 queries/day hard limit) — use it as the zero-cost first pass or alongside kagi-search: Marginalia to discover obscure/indie/old-web sources, Kagi for mainstream coverage and full-page extraction. Triggers: 'search the small web', 'indie web', 'old web', 'find blogs about', 'non-commercial sources', 'obscure pages on', 'retro', searching topics where SEO spam drowns signal (recipes, hobbies, DIY, niche tech), or any research task where kagi-search is also in play. Requires MARGINALIA_API_KEY env var or ~/.config/marginalia/api_key file (falls back to shared 'public' key)."
---

# Marginalia Search

One endpoint, one script. `GET https://api2.marginalia-search.com/search?query=...` with the key in the **`API-Key` header**. Marginalia is an independent, open-source (AGPL) search engine that favors text-heavy, low-javascript, non-commercial pages — personal sites, forums, academic pages, the old web. Results are licensed **CC-BY-NC-SA 4.0** (non-commercial keys).

Everything below verified against the live API on **2026-09-01**.

## Setup

Script paths below (`./scripts/...`) are relative to this skill's directory.

Free non-commercial API keys are issued on request — see https://about.marginalia-search.com/article/api/ for how to ask. The scripts read `MARGINALIA_API_KEY`, else `~/.config/marginalia/api_key`:

```bash
mkdir -p ~/.config/marginalia
printf '%s' 'YOUR_KEY' > ~/.config/marginalia/api_key
chmod 600 ~/.config/marginalia/api_key
```

Without a key the script falls back to the shared `public` key, which works for trying things out but is heavily rate-limited (503 when exhausted) and cannot manage filters.

**A free non-commercial key allows 1000 queries/day, HARD limit** (set `MARGINALIA_QUOTA_LIMIT` if yours differs). The script prints a `marginalia quota: N/1000 queries today` line to stderr after each call (local ledger at `${XDG_STATE_HOME:-~/.local/state}/marginalia/usage.jsonl`; disable with `MARGINALIA_LEDGER=off`). The ledger only counts calls made through the script — raw curl bypasses it, so treat the count as a floor. "Today" is the UTC day, matching the quota window.

`../web-research/scripts/search-cost.sh` shows today's count alongside Kagi/Exa spend (in pi, the bundled `search-cost` extension also shows `marg used/1k` in the footer, amber at 80%, red at 95%).

Requires `bash`, `curl`, `python3` (stdlib only).

## Usage

```bash
./scripts/search.sh "linear b"                       # default 10 results
./scripts/search.sh -c 20 "mycenaean pottery"        # count 1-100
./scripts/search.sh -p 2 "mycenaean pottery"         # page (1-indexed; response has `pages`)
./scripts/search.sh -d 1 "static site generator"     # max 1 result per domain
./scripts/search.sh -t 250 "rare query"              # query timeout ms (50-250)
./scripts/search.sh -f myfilter "retro computing"    # use a custom filter
./scripts/search.sh -n 1 "query"                     # experimental NSFW reduction
```

### Query operators (inline in the query string — all verified live)

| Operator | Example | Effect |
|---|---|---|
| `"..."` | `"row hammer attack"` | exact phrase |
| `-term` | `linear b -wikipedia` | exclude term |
| `site:` | `site:en.wikipedia.org linear b` | hard-scope to domain |
| `tld:` | `tld:edu mycenaean` | scope to top-level domain |
| `year>` / `year<` | `commodore 64 year<1996` | estimated publication year (janky but works) |
| `format:` | `format:pdf mycenaean` | document format (`html`, `pdf`, ...) |

### Response shape

```json
{
  "license": "CC-BY-NC-SA 4.0",
  "page": 1,
  "pages": 11,
  "query": "linear b",
  "results": [
    {
      "url": "https://en.wikipedia.org/wiki/Linear_B",
      "title": "Linear B",
      "description": "…plain-text snippet, no HTML tags…",
      "quality": 3.05,
      "format": "html",
      "resultsFromDomain": 9711,
      "details": [[]]
    }
  ]
}
```

Gotchas verified against the live API:

- **`quality` is LOWER = better** — results come back sorted ascending by it. Don't treat it as a score to maximize.
- `details` is always `[[]]` in practice — ignore it.
- Descriptions are plain text (no HTML highlight tags, unlike Kagi snippets).
- **Out-of-range params fail open**, not with an error: `count=500` silently returns ~100 results. Don't rely on the API to validate your params.
- Empty result set is `{"pages": 0, "results": []}` with HTTP 200.
- No rate-limit headers; the only quota signal is HTTP 503 when you hit the wall. Trust the local ledger.
- `resultsFromDomain` is the total number of docs indexed from that domain — useful as a big-site vs. small-site signal (a personal blog is 1-100, wikipedia is ~180K).

## Custom filters

Per-key server-side filters (not available on the `public` key). Created once, then referenced by name via `-f NAME` on any search. `POST`/`DELETE` return **202 Accepted**; effect is immediate in practice.

```bash
./scripts/filter.sh list
./scripts/filter.sh create smallweb - <<'XML'
<?xml version="1.0"?>
<filter>
    <limit param="size" type="lt" value="1000"/>
    <temporal-bias>OLD</temporal-bias>
</filter>
XML
./scripts/search.sh -f smallweb "personal wiki software"
./scripts/filter.sh get smallweb
./scripts/filter.sh delete smallweb
```

Full XML element reference is in the header comment of `scripts/filter.sh`: `domains-include`/`exclude`/`promote`, `terms-require`/`exclude`/`promote`, `temporal-bias` (`OLD`|`RECENT`|`NONE`), and `limit` on `year`/`quality` (js-heaviness)/`size` (docs per domain)/`rank` (pagerank 0-255). A filter editor UI lives at https://marginalia-search.com/filters.

## When to use Marginalia vs. Kagi

For multi-source research, prefer the **web-research** skill (`../web-research/`) — its `meta-search.sh` fans out to Kagi + Marginalia (+ Exa with `-e all`) in parallel, dedupes, and flags URLs multiple indexes agree on. The table below is for choosing a single engine directly.

The two skills are designed to be used **together**. Marginalia is free; Kagi costs $0.012/search + $0.004/extract. Marginalia has no content-extraction — it returns snippets only.

| Situation | Use |
|---|---|
| Indie/old-web discovery: blogs, forums, personal sites, niche hobby pages | **Marginalia** |
| SEO-spam-prone topics (recipes, DIY, product experience, "best X") | **Marginalia first** — its ranking penalizes commercial spam |
| Pre-web-2.0 / retro content, `year<` filtering | **Marginalia** (Kagi has no old-web bias) |
| Mainstream facts, news, current events | **Kagi** (Marginalia's index is smaller and crawls slowly) |
| Need full page content for synthesis | **Kagi** search+extract, or Marginalia to find the URL then `../web-research/scripts/fetch-page.sh URL` (Exa $0.001 → Kagi $0.004 → free fallbacks) |
| Cheap breadth pass before spending Kagi budget | **Marginalia** (free) then Kagi on what's missing |
| X/Twitter, images, videos, podcasts | **Kagi only** |
| Domain-restricted lookup on a big mainstream site | Either works (`site:` on both); Marginalia is free |

**Combined research pattern:** run a Marginalia search (free) and a Kagi count=0 search in parallel for breadth; dedupe; extract only the winning URLs via Kagi extract. This keeps cost at ~$0.012 + $0.004×N instead of paying for extraction on everything.

**Quota discipline:** 1000/day sounds like a lot but hard-stops at 503. In tight loops (query expansion, eval harnesses) batch and dedupe queries; the ledger line on stderr tells you where you stand.

## Errors

Plain-text or empty bodies, no JSON error envelope:

- **400** — malformed request; missing key gives `Missing API-Key header`.
- **401** — key rejected (empty body). Check `~/.config/marginalia/api_key` / `MARGINALIA_API_KEY`.
- **503** — rate limit (daily quota on your key; shared limit on `public`). Hard limit — no retry will help until the day rolls over (UTC).
- **5xx other** — server-side; the whole engine runs on modest hardware, retry once after a few seconds.

## Ecosystem

- API docs: https://about.marginalia-search.com/article/api/ (updated 2025-12-08).
- Old deprecated API at `api.marginalia.nu/public/search/...` — path-based key, fewer params, no filters. Don't build on it.
- Source: https://git.marginalia.nu/ (AGPL). Datasets: https://downloads.marginalia.nu/.
- Key/terms contact: contact@marginalia-search.com. Commercial keys exist if attribution/NC terms ever become a problem.
