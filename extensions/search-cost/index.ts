/**
 * search-cost — pi extension: unified footer display for all three search
 * engines (optional; the skills work without it, and in other harnesses
 * skills/web-research/scripts/search-cost.sh prints the same numbers).
 *
 * One always-visible, labeled segment:
 *
 *     kagi $0.12 · exa $0.034 · marg 19/1k
 *
 * Each part is colored independently (dim → warning → error) by its own
 * thresholds. Money engines (kagi, exa) track USD from their ledgers;
 * Marginalia tracks query count against the 1000/day hard limit (UTC window).
 *
 * Ledgers (written by the skills' scripts; honors XDG_STATE_HOME and the
 * per-engine KAGI_LEDGER / EXA_LEDGER / MARGINALIA_LEDGER overrides):
 *   ~/.local/state/kagi/usage.jsonl        {ts, usd, ...}
 *   ~/.local/state/exa/usage.jsonl         {ts, usd, ...}
 *   ~/.local/state/marginalia/usage.jsonl  {ts, q}
 *
 * Env overrides:
 *   KAGI_COST_WARN / KAGI_COST_ALERT           (USD/day, default 1 / 5)
 *   EXA_COST_WARN / EXA_COST_ALERT             (USD/day, default 0.33 / 2)
 *   MARGINALIA_QUOTA_WARN / _ALERT             (fraction, default 0.8 / 0.95)
 *   MARGINALIA_QUOTA_LIMIT                     (default 1000)
 *   SEARCH_COST_SCOPE   today | session | month | all  (default today)
 *
 * Command: /search-cost [today|session|month|all|reset <engine>]
 */

import { existsSync, readFileSync, renameSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Rec = { ts: string; usd?: number; q?: string; ep?: string };
const SCOPES = ["today", "session", "month", "all"] as const;
type Scope = (typeof SCOPES)[number];
const ENGINES = ["kagi", "exa", "marginalia"] as const;
type Engine = (typeof ENGINES)[number];

function statePath(engine: Engine): string {
	const env = process.env[`${engine.toUpperCase()}_LEDGER`];
	if (env && env !== "off") return env;
	const state = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
	return join(state, engine, "usage.jsonl");
}

function num(v: string | undefined, fallback: number): number {
	const n = Number(v);
	return Number.isFinite(n) ? n : fallback;
}

export default function (pi: ExtensionAPI) {
	const sessionStart = Date.now();
	const thresholds = {
		kagi: { warn: num(process.env.KAGI_COST_WARN, 1), alert: num(process.env.KAGI_COST_ALERT, 5) },
		exa: { warn: num(process.env.EXA_COST_WARN, 0.33), alert: num(process.env.EXA_COST_ALERT, 2) },
	};
	const margLimit = num(process.env.MARGINALIA_QUOTA_LIMIT, 1000);
	const margWarn = num(process.env.MARGINALIA_QUOTA_WARN, 0.8);
	const margAlert = num(process.env.MARGINALIA_QUOTA_ALERT, 0.95);
	const envScope = process.env.SEARCH_COST_SCOPE as Scope | undefined;
	let scope: Scope = envScope && SCOPES.includes(envScope) ? envScope : "today";

	const caches: Record<Engine, { recs: Rec[]; key: string }> = {
		kagi: { recs: [], key: "" },
		exa: { recs: [], key: "" },
		marginalia: { recs: [], key: "" },
	};

	function load(engine: Engine): Rec[] {
		const path = statePath(engine);
		const cache = caches[engine];
		try {
			if (!existsSync(path)) {
				cache.recs = [];
				cache.key = "";
				return cache.recs;
			}
			const st = statSync(path);
			const key = `${st.mtimeMs}:${st.size}`;
			if (key === cache.key) return cache.recs;
			const recs: Rec[] = [];
			for (const line of readFileSync(path, "utf8").split("\n")) {
				const t = line.trim();
				if (!t) continue;
				try {
					const p = JSON.parse(t) as Rec;
					if (p && typeof p.ts === "string") recs.push(p);
				} catch {
					// torn line
				}
			}
			cache.recs = recs;
			cache.key = key;
			return recs;
		} catch {
			return cache.recs;
		}
	}

	function since(s: Scope, utc: boolean): number {
		const now = new Date();
		switch (s) {
			case "today":
				return utc
					? Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
					: new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
			case "month":
				return utc
					? Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)
					: new Date(now.getFullYear(), now.getMonth(), 1).getTime();
			case "session":
				return sessionStart;
			case "all":
				return 0;
		}
	}

	function usd(engine: "kagi" | "exa", s: Scope): { usd: number; calls: number } {
		const cutoff = since(s, false);
		let total = 0;
		let calls = 0;
		for (const r of load(engine)) {
			const at = Date.parse(r.ts);
			if (!Number.isFinite(at) || at < cutoff) continue;
			total += r.usd ?? 0;
			calls += 1;
		}
		return { usd: total, calls };
	}

	function margCount(s: Scope): number {
		// marginalia quota window is UTC-midnight regardless of scope=today
		const cutoff = since(s, true);
		let n = 0;
		for (const r of load("marginalia")) {
			const at = Date.parse(r.ts);
			if (Number.isFinite(at) && at >= cutoff) n += 1;
		}
		return n;
	}

	function money(v: number): string {
		if (v >= 10) return `$${v.toFixed(2)}`;
		if (v >= 0.01) return `$${v.toFixed(2)}`;
		return v > 0 ? `$${v.toFixed(3)}` : "$0";
	}

	function colour(v: number, warn: number, alert: number): "dim" | "warning" | "error" {
		return v >= alert ? "error" : v >= warn ? "warning" : "dim";
	}

	// Brand colors, pulled from each engine's own assets (verified 2026-09-02):
	// kagi favicon dominant #FFB319 · exa.ai CSS #1F40ED · marginalia margeblue #3E5F6F
	// (marginalia's slate reads too dark on dark themes; lightened variant keeps the hue)
	const BRAND: Record<Engine, [number, number, number]> = {
		kagi: [255, 179, 25],
		exa: [95, 122, 255],
		marginalia: [124, 163, 183],
	};

	function brand(engine: Engine, text: string): string {
		const [r, g, b] = BRAND[engine];
		return `\x1b[38;2;${r};${g};${b}m${text}\x1b[39m`;
	}

	function render(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		const theme = ctx.ui.theme;
		const k = usd("kagi", scope);
		const e = usd("exa", scope);
		const m = margCount(scope);
		// Name in brand color (recognition); value in status color (alarm).
		// Kagi's brand IS warning-yellow, so alarms live on the value only.
		const parts = [
			brand("kagi", "kagi ") +
				theme.fg(colour(k.usd, thresholds.kagi.warn, thresholds.kagi.alert), money(k.usd)),
			brand("exa", "exa ") +
				theme.fg(colour(e.usd, thresholds.exa.warn, thresholds.exa.alert), money(e.usd)),
			brand("marginalia", "marg ") +
				theme.fg(
					colour(m / margLimit, margWarn, margAlert),
					`${m}/${margLimit >= 1000 ? `${margLimit / 1000}k` : margLimit}`,
				),
		];
		const label = scope === "today" ? "" : theme.fg("dim", ` (${scope})`);
		ctx.ui.setStatus("search", `⌕ ${parts.join(theme.fg("dim", " · "))}${label}`);
	}

	pi.on("session_start", async (_e, ctx) => render(ctx));
	pi.on("turn_end", async (_e, ctx) => render(ctx));
	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName === "bash") render(ctx);
	});
	pi.on("user_bash", (_e, ctx) => {
		setTimeout(() => render(ctx), 1500);
	});

	pi.registerCommand("search-cost", {
		description: "Search engines usage (arg: today|session|month|all|reset <kagi|exa|marginalia>)",
		getArgumentCompletions: (prefix: string) => {
			const items = [...SCOPES, "reset kagi", "reset exa", "reset marginalia"].map((v) => ({
				value: v,
				label: v,
			}));
			const filtered = items.filter((i) => i.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const arg = (args || "").trim();

			if (arg.startsWith("reset")) {
				const target = arg.split(/\s+/)[1] as Engine | undefined;
				if (!target || !ENGINES.includes(target)) {
					ctx.ui.notify("usage: /search-cost reset <kagi|exa|marginalia>", "warning");
					return;
				}
				const path = statePath(target);
				try {
					if (existsSync(path)) {
						renameSync(path, `${path}.${new Date().toISOString().slice(0, 10)}.bak`);
						caches[target].key = "";
						caches[target].recs = [];
					}
					render(ctx);
					ctx.ui.notify(`${target} ledger archived → ${path}.*.bak`, "info");
				} catch (err) {
					ctx.ui.notify(`reset failed: ${String(err)}`, "error");
				}
				return;
			}

			if (SCOPES.includes(arg as Scope)) {
				scope = arg as Scope;
				render(ctx);
			}

			const lines: string[] = ["Search engine usage"];
			for (const name of SCOPES) {
				const k = usd("kagi", name);
				const e = usd("exa", name);
				const m = margCount(name);
				lines.push(
					`  ${name.padEnd(8)} kagi ${money(k.usd).padStart(7)} (${k.calls})   exa ${money(e.usd).padStart(7)} (${e.calls})   marg ${m}${name === "today" ? `/${margLimit} (resets UTC midnight)` : ""}`,
				);
			}
			const mToday = margCount("today");
			if (mToday / margLimit >= margWarn) {
				lines.push(`  ⚠ marginalia at ${Math.round((mToday / margLimit) * 100)}% of daily HARD limit`);
			}
			lines.push(`  exa free credits: $10/mo (~$0.33/day averages free)`);
			lines.push(`  footer scope: ${scope}   ledgers: ~/.local/state/{kagi,exa,marginalia}/usage.jsonl`);
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});
}
