# search-three

Web research skills for coding agents, built on three search engines that find things in different ways:

| Engine | How it retrieves | Good at | Cost |
|---|---|---|---|
| **Kagi** | keyword + quality re-ranking | precise lookups, `site:`/`filetype:`, news, X/Twitter, clean page extraction | $0.012/search, $0.004/page extract |
| **Exa** | neural embeddings | "find pages *like* this", conceptual queries, papers/companies/repos, cheap extraction | $0.007/search, $0.001/page ($10 free credit/month) |
| **Marginalia** | keyword, anti-SEO index | personal sites, forums, old web, topics buried under SEO spam | free (1000 queries/day) |

When two or three of these independently return the same URL, that page is very likely relevant. The coordinator skill is built around that signal.

## What's inside

```
skills/
├── web-research/        coordinator: when to use which engine, research recipes
│   └── scripts/
│       ├── meta-search.sh   parallel fan-out to 2–3 engines, merged + deduped, agreement flagged
│       ├── fetch-page.sh    URL → markdown, fallback ladder: exa → kagi → curl → playwright → camoufox → wayback
│       ├── doctor.sh        setup check (tools, keys, optional extras)
│       └── search-cost.sh   spend/quota summary from the local ledgers
├── kagi-search/         Kagi v1 search + extract
├── exa-search/          Exa search, find-similar, contents
└── marginalia-search/   Marginalia search + custom filters
extensions/search-cost/  (pi only, optional) live cost footer + /search-cost command
```

Each skill is a folder with a `SKILL.md` ([Agent Skills](https://agentskills.io) format) and bash scripts. The agent reads the SKILL.md when a task matches and runs the scripts. The four folders need to stay next to each other, because `web-research` calls the engine scripts through `../<skill>/scripts/`.

## Install

### Claude Code

```
/plugin marketplace add tomooshi/search-three
/plugin install search-three@search-three
```

Restart Claude Code. The skills show up as `search-three:web-research`, `search-three:kagi-search`, and so on.

### pi

```bash
pi install git:github.com/tomooshi/search-three
```

This also loads the optional `search-cost` footer extension. To skip it, run `pi config` and disable the extension.

### Anything else (Codex, OpenCode, Cursor, or a plain skills folder)

```bash
git clone https://github.com/tomooshi/search-three.git
cd search-three
./install.sh claude          # or: pi | agents | codex | /path/to/your/skills
```

`install.sh` symlinks by default, so a later `git pull` updates the skills. Use `--copy` to copy the folders instead, and `--force` to replace skills that already use these names.

## Requirements

- `bash`, `curl`, `python3`. The engine scripts only use the Python standard library. Works on Linux and macOS; on Windows, use WSL or Git Bash.
- Optional extras for `fetch-page.sh`'s free fallback steps. Each missing extra disables one step and the ladder skips it:
  - `pip install beautifulsoup4` enables the curl / wayback steps and is also needed by the browser steps
  - `pip install playwright && playwright install chromium` renders JS-heavy pages
  - Camoufox, a Firefox build that resists bot detection, for pages that block normal headless browsers:
    ```bash
    python3 -m venv ~/.venvs/camoufox
    ~/.venvs/camoufox/bin/pip install 'camoufox[geoip]' beautifulsoup4
    ~/.venvs/camoufox/bin/python -m camoufox fetch
    ```

If your system Python won't allow `pip install` (PEP 668), put the extras in a venv and set `FETCH_PYTHON=/path/to/venv/bin/python`.

## API keys

Each script checks an environment variable first, then a key file:

| Engine | Get a key | Env var | Key file |
|---|---|---|---|
| Kagi | https://kagi.com/api (needs a Kagi account with API credit) | `KAGI_API_KEY` | `~/.config/kagi/api_key` |
| Exa | https://dashboard.exa.ai (free $10/month credit) | `EXA_API_KEY` | `~/.config/exa/api_key` |
| Marginalia | free non-commercial key on request, see https://about.marginalia-search.com/article/api/ | `MARGINALIA_API_KEY` | `~/.config/marginalia/api_key` |

```bash
for e in kagi exa marginalia; do mkdir -p ~/.config/$e; done
printf '%s' 'KAGI_KEY'       > ~/.config/kagi/api_key
printf '%s' 'EXA_KEY'        > ~/.config/exa/api_key
printf '%s' 'MARGINALIA_KEY' > ~/.config/marginalia/api_key
chmod 600 ~/.config/{kagi,exa,marginalia}/api_key
```

Without a Marginalia key, the scripts use Marginalia's shared `public` key. That's enough to try things out, but it runs out quickly. Kagi and Exa have no fallback. If you skip one of them, leave it out of the fan-out: `meta-search.sh -e marginalia,exa "query"`.

## Check the setup

```bash
skills/web-research/scripts/doctor.sh          # offline: tools, keys, optional extras
skills/web-research/scripts/doctor.sh --live   # plus one real query per engine (~$0.02 total)
```

With the Claude Code plugin, you can also just ask: *"run the web-research doctor script"*.

## Try it

```bash
cd skills/web-research
./scripts/meta-search.sh "static site generators for personal wikis"          # kagi + marginalia
./scripts/meta-search.sh -e all "essays arguing against infinite scroll"       # + exa
./scripts/fetch-page.sh https://example.com/some/article
./scripts/search-cost.sh
```

Or ask your agent something like *"research what practitioners say about X, find the best sources"*. The `web-research` skill tells it which engine to use and how.

## Handing this to your agent

If you'd rather have your agent set this up and adapt it, paste this:

> Install the skills from https://github.com/tomooshi/search-three for this harness (read its README). Then run `skills/web-research/scripts/doctor.sh` and walk me through anything marked ✗: API keys, missing tools. Don't put keys in the repo. Use `~/.config/<engine>/api_key` with chmod 600. If a script path doesn't resolve in this harness, fix it so the four skill folders stay side by side, and don't hardcode my home directory.

## Cost tracking

Every script call adds one JSON line to a local ledger:

```
${XDG_STATE_HOME:-~/.local/state}/kagi/usage.jsonl
${XDG_STATE_HOME:-~/.local/state}/exa/usage.jsonl
${XDG_STATE_HOME:-~/.local/state}/marginalia/usage.jsonl
```

`search-cost.sh` summarizes spend for today, this month, and all time. The ledgers only count calls made through these scripts. Each provider's dashboard has the actual bill.

## Configuration

| Variable | Effect |
|---|---|
| `KAGI_API_KEY`, `EXA_API_KEY`, `MARGINALIA_API_KEY` | API keys (override the key files) |
| `KAGI_LEDGER`, `EXA_LEDGER`, `MARGINALIA_LEDGER` | ledger path, or `off` |
| `KAGI_RATE_SEARCH`, `KAGI_RATE_EXTRACT` | Kagi prices used by the ledger (defaults: 0.012 / 0.004) |
| `MARGINALIA_QUOTA_LIMIT` | daily Marginalia quota (default 1000) |
| `FETCH_PYTHON` | Python for the bs4/playwright fetch steps (default `python3`) |
| `CAMOUFOX_PYTHON` | Python with camoufox (default `~/.venvs/camoufox/bin/python` if it exists) |
| `SEARCH_SKILLS_DIR` | where the four skill folders live, if they aren't siblings |

pi footer extension only: `KAGI_COST_WARN`/`_ALERT`, `EXA_COST_WARN`/`_ALERT`, `MARGINALIA_QUOTA_WARN`/`_ALERT`, `SEARCH_COST_SCOPE`.

## Notes

- API behavior noted in the SKILL.md files (response shapes, quirks, silently ignored parameters) was checked against the live APIs in Aug–Sep 2026. Some of it will drift. If a documented flag stops working, trust what the API returns.
- Marginalia results are CC-BY-NC-SA 4.0 on non-commercial keys.
- `fetch-page.sh`'s browser steps are for reading public pages. Respect site terms.

## License

MIT
