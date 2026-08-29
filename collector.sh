#!/usr/bin/env bash
# OpenCode Go collector — limits + catalog from Zen API, current pricing from models.dev.
set -uo pipefail

GO_BASE="${OPENCODE_GO_BASE:-https://opencode.ai/zen/go/v1}"
MODELS_DEV="${OPENCODE_MODELS_DEV:-https://models.dev/api.json}"
AUTH_JSON="${OPENCODE_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"

MAX_CATALOG="${OPENCODE_MAX_CATALOG:-200}"
case "$MAX_CATALOG" in *[!0-9]*|"") MAX_CATALOG=200 ;; esac
MAX_CATALOG=$(( MAX_CATALOG > 500 ? 500 : (MAX_CATALOG < 1 ? 1 : MAX_CATALOG) ))

# ---- model catalog (public); stream + cap, never hold full HTTP body ------------
catalog=$(curl -sS -m 15 "$GO_BASE/models" 2>/dev/null \
  | jq -c --argjson max "$MAX_CATALOG" '
      [.data[]?.id // empty | select(. != "" and (type == "string") and length <= 128)] | .[:$max]
    ' 2>/dev/null || echo '[]')
[[ -z $catalog || $catalog == 'null' ]] && catalog='[]'

# ---- current $/1M pricing; only entries for catalog IDs, streamed --------------
pricing='{}'
if [[ $catalog != '[]' ]]; then
  pricing=$(curl -sS -m 15 "$MODELS_DEV" 2>/dev/null \
    | jq -c --argjson ids "$catalog" '
        (.["opencode-go"].models // {}) | to_entries
        | map(select(.value.cost and (.key as $k | ($ids | index($k)))))
        | map({key: .key, value: {
            in: (.value.cost.input // 0),
            out: (.value.cost.output // 0),
            cache: (.value.cost.cache_read // 0)
          }})
        | from_entries
      ' 2>/dev/null || echo '{}')
fi
[[ -z $pricing || $pricing == 'null' ]] && pricing='{}'

# ---- subscription limit windows (needs Go key) --------------------------------
# Key stays in jq→curl stdin; never on curl argv and not stored in a shell var.
windows='null'
if [[ -r $AUTH_JSON ]]; then
  windows=$(
    jq -r '.["opencode-go"].key // empty | select(length > 0)
      | "header = \"Authorization: Bearer \(.)\""' "$AUTH_JSON" 2>/dev/null \
      | curl -sS -m 10 --config - "$GO_BASE/usage" 2>/dev/null \
      | jq -c '{rolling:.usage.rolling,weekly:.usage.weekly,monthly:.usage.monthly}' 2>/dev/null \
      || echo 'null'
  )
fi
[[ -z $windows || $windows == 'null' ]] && windows='null'

jq -cn \
  --argjson catalog "$catalog" \
  --argjson pricing "$pricing" \
  --arg windows "$windows" \
  --arg status ok \
  --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{status:$status,windows:($windows|fromjson),catalog:$catalog,pricing:$pricing,updatedAt:$updatedAt,error:""}'
