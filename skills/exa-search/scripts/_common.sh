# shared by exa scripts: key loading, request, ledger. Source, don't execute.

exa_key() {
	API_KEY="${EXA_API_KEY:-}"
	if [ -z "$API_KEY" ] && [ -r "$HOME/.config/exa/api_key" ]; then
		API_KEY="$(cat "$HOME/.config/exa/api_key")"
	fi
	if [ -z "$API_KEY" ]; then
		echo "Error: no EXA_API_KEY env var and no ~/.config/exa/api_key file" >&2
		exit 1
	fi
}

# exa_post ENDPOINT BODY LEDGER_EP LEDGER_QUERY
exa_post() {
	local endpoint="$1" body="$2" ep="$3" q="$4"
	local response http_code body_out
	response="$(curl -s -w "\n%{http_code}" \
		-H "x-api-key: $API_KEY" \
		-H "Content-Type: application/json" \
		-d "$body" \
		"https://api.exa.ai/$endpoint")"
	http_code="$(echo "$response" | tail -n1)"
	body_out="$(echo "$response" | sed '$d')"
	if [ "$http_code" != "200" ]; then
		echo "Exa API $http_code: $body_out" >&2
		exit 1
	fi
	# Ledger: Exa reports its own cost in the response (costDollars.total).
	if [ "${EXA_LEDGER:-}" != "off" ]; then
		local ledger="${EXA_LEDGER:-${XDG_STATE_HOME:-$HOME/.local/state}/exa/usage.jsonl}"
		mkdir -p "$(dirname "$ledger")" 2>/dev/null || true
		printf '%s' "$body_out" | EP="$ep" Q="$q" LEDGER="$ledger" python3 -c '
import json, os, sys, datetime
try:
    d = json.load(sys.stdin)
    usd = (d.get("costDollars") or {}).get("total", 0)
    rec = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "ep": os.environ["EP"], "usd": usd, "q": os.environ["Q"][:200]}
    with open(os.environ["LEDGER"], "a") as f:
        f.write(json.dumps(rec) + "\n")
except Exception:
    pass' 2>/dev/null || true
	fi
	echo "$body_out"
}
