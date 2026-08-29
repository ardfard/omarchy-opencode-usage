#!/usr/bin/env bash
# OpenCode Go usage collector — local opencode-go rows from opencode.db, plus
# Go subscription limit windows from the Zen API when a key is present.
# Emits one JSON object consumed by Model.parseCollector().
set -uo pipefail

DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
DAYS="${1:-${OPENCODE_USAGE_DAYS:-7}}"
case "$DAYS" in *[!0-9]*|"") DAYS=7 ;; esac
DAYS=$(( DAYS > 30 ? 30 : (DAYS < 1 ? 1 : DAYS) ))

[[ -r $DB ]] || { jq -cn '{status:"no database",error:"opencode.db not found: '"$DB"'"}'; exit 0; }

cutoff=$(( $(date +%s)*1000 - DAYS*86400000 ))

run_sql() {
  sqlite3 -readonly "file:$DB?mode=ro" "$1" 2>/dev/null
}

# ---- per-model rollup (opencode-go assistant messages only)
models=$(run_sql "
SELECT COALESCE(json_group_array(json_object(
  'provider', provider, 'model', model, 'messages', messages,
  'tokens', json_object('total',ttotal,'input',tin,'output',tout,'reasoning',treason,'cacheRead',tcr,'cacheWrite',tcw),
  'cost', cost)), '[]')
FROM (
  SELECT
    COALESCE(json_extract(data,'\$.providerID'),'?') AS provider,
    COALESCE(json_extract(data,'\$.modelID'),'?')    AS model,
    COUNT(*)                                                          AS messages,
    SUM(COALESCE(json_extract(data,'\$.tokens.total'),0))             AS ttotal,
    SUM(COALESCE(json_extract(data,'\$.tokens.input'),0))             AS tin,
    SUM(COALESCE(json_extract(data,'\$.tokens.output'),0))            AS tout,
    SUM(COALESCE(json_extract(data,'\$.tokens.reasoning'),0))         AS treason,
    SUM(COALESCE(json_extract(data,'\$.tokens.cache.read'),0))        AS tcr,
    SUM(COALESCE(json_extract(data,'\$.tokens.cache.write'),0))       AS tcw,
    ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4)            AS cost
  FROM message
  WHERE time_created > $cutoff
    AND json_extract(data,'\$.role')='assistant'
    AND json_extract(data,'\$.providerID')='opencode-go'
  GROUP BY 1, 2
);") || models='[]'
[[ -z $models ]] && models='[]'

# ---- per-day totals (opencode-go assistant messages only)
days=$(run_sql "
SELECT COALESCE(json_group_array(json_object(
  'date', d, 'messages', m, 'tokens', t, 'cost', c)), '[]')
FROM (
  SELECT date(time_created/1000,'unixepoch','localtime')                AS d,
         COUNT(*)                                                       AS m,
         SUM(COALESCE(json_extract(data,'\$.tokens.total'),0))          AS t,
         ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4)         AS c
  FROM message
  WHERE time_created > $cutoff
    AND json_extract(data,'\$.role')='assistant'
    AND json_extract(data,'\$.providerID')='opencode-go'
  GROUP BY d ORDER BY d
);") || days='[]'
[[ -z $days ]] && days='[]'

# ---- fill missing days so the sparkline is continuous, oldest → today
filled=$(jq -cn --argjson got "$days" --argjson n "$DAYS" '
  (now | floor) as $end |
  [ range($end - ($n - 1)*86400; $end + 1; 86400) | strftime("%Y-%m-%d") ] as $want |
  [ $want[] | . as $d | ($got | map(select(.date == $d))[0]) //
    {date:$d, messages:0, tokens:0, cost:0} ]') || filled='[]'

totals=$(jq -cn --argjson m "$models" \
  '{messages:($m|map(.messages)|add//0), tokens:($m|map(.tokens.total)|add//0), cost:($m|map(.cost)|add//0)}')

# ---- OpenCode Go subscription limits (rolling 5h / weekly / monthly) ----
# Best-effort: no key -> null windows, no error. Same endpoint as local.opencode-go.
AUTH_JSON="${OPENCODE_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"
GO_URL="https://opencode.ai/zen/go/v1/usage"
windows='null'
if [[ -r $AUTH_JSON ]]; then
  go_key=$(jq -r '.["opencode-go"].key // empty' "$AUTH_JSON" 2>/dev/null || true)
  if [[ -n $go_key ]]; then
    resp=$(printf 'header = "Authorization: Bearer %s"\n' "$go_key" | curl -sS -m 10 --config - "$GO_URL" 2>/dev/null) || true
    if [[ -n $resp ]]; then
      windows=$(printf '%s' "$resp" | jq -c '{rolling:.usage.rolling,weekly:.usage.weekly,monthly:.usage.monthly}' 2>/dev/null || echo 'null')
    fi
  fi
fi
[[ -z $windows || $windows == 'null' ]] && windows='null'

jq -cn \
  --argjson models "$models" \
  --argjson days "$filled" \
  --argjson totals "$totals" \
  --arg windows "$windows" \
  --arg status ok \
  --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{status:$status,windows:($windows|fromjson),models:$models,days:$days,totals:$totals,updatedAt:$updatedAt,error:""}'
