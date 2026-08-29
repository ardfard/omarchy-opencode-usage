#!/usr/bin/env bash
# OpenCode Go collector — limits + catalog from Zen API, current pricing from models.dev.
set -uo pipefail

GO_BASE="${OPENCODE_GO_BASE:-https://opencode.ai/zen/go/v1}"
MODELS_DEV="${OPENCODE_MODELS_DEV:-https://models.dev/api.json}"
AUTH_JSON="${OPENCODE_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"

# ---- model catalog (public) -----------------------------------------------
catalog='[]'
resp=$(curl -sS -m 15 "$GO_BASE/models" 2>/dev/null) || true
if [[ -n $resp ]]; then
  catalog=$(printf '%s' "$resp" | jq -c '[.data[]?.id // empty] | map(select(. != ""))' 2>/dev/null || echo '[]')
fi
[[ -z $catalog ]] && catalog='[]'

# ---- current $/1M pricing (models.dev tracks promos for opencode-go) --------
pricing='{}'
resp=$(curl -sS -m 15 "$MODELS_DEV" 2>/dev/null) || true
if [[ -n $resp ]]; then
  pricing=$(printf '%s' "$resp" | jq -c '
    (.["opencode-go"].models // {}) | to_entries
    | map(select(.value.cost))
    | map({key: .key, value: {
        in: (.value.cost.input // 0),
        out: (.value.cost.output // 0),
        cache: (.value.cost.cache_read // 0)
      }})
    | from_entries
  ' 2>/dev/null || echo '{}')
fi
[[ -z $pricing ]] && pricing='{}'

# ---- subscription limit windows (needs Go key) ----------------------------
windows='null'
if [[ -r $AUTH_JSON ]]; then
  go_key=$(jq -r '.["opencode-go"].key // empty' "$AUTH_JSON" 2>/dev/null || true)
  if [[ -n $go_key ]]; then
    resp=$(printf 'header = "Authorization: Bearer %s"\n' "$go_key" | curl -sS -m 10 --config - "$GO_BASE/usage" 2>/dev/null) || true
    if [[ -n $resp ]]; then
      windows=$(printf '%s' "$resp" | jq -c '{rolling:.usage.rolling,weekly:.usage.weekly,monthly:.usage.monthly}' 2>/dev/null || echo 'null')
    fi
  fi
fi
[[ -z $windows || $windows == 'null' ]] && windows='null'

jq -cn \
  --argjson catalog "$catalog" \
  --argjson pricing "$pricing" \
  --arg windows "$windows" \
  --arg status ok \
  --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{status:$status,windows:($windows|fromjson),catalog:$catalog,pricing:$pricing,updatedAt:$updatedAt,error:""}'
