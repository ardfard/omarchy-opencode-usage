.pragma library

// ---- OpenCode Go limit windows -------------------------------------------

var ROLLING_MS = 5 * 60 * 60 * 1000
var WEEK_MS = 7 * 24 * 60 * 60 * 1000
var MONTHLY_MS = 30 * 24 * 60 * 60 * 1000

function windowMs(kind) {
  if (kind === "rolling") return ROLLING_MS
  if (kind === "monthly") return MONTHLY_MS
  return WEEK_MS
}

// {status, percent(0-100), resetsAt, limitDollars} -> normalized {kind, percent, remaining, resetMs, limitDollars}
function normalizeWindow(window, kind, nowMs) {
  if (!window) return null
  var percent = clamp(number(window.percent, 0) / 100, 0, 1)
  var resetMs = Date.parse(String(window.resetsAt || ""))
  if (!isFinite(resetMs)) resetMs = 0
  return {
    kind: String(kind || "weekly"),
    percent: percent,
    remaining: 1 - percent,
    resetMs: resetMs,
    limitDollars: number(window.limitDollars, 0)
  }
}

function expectedRemaining(window, nowMs) {
  if (!window || window.resetMs <= 0) return 0
  return clamp((window.resetMs - nowMs) / windowMs(window.kind), 0, 1)
}

function behindPace(window, nowMs) {
  if (!window || window.resetMs <= 0) return false
  return window.remaining + 0.0005 < expectedRemaining(window, nowMs)
}

function paceText(window, nowMs) {
  if (!window) return "No limit"
  var difference = window.remaining - expectedRemaining(window, nowMs)
  var points = Math.round(Math.abs(difference) * 100)
  if (points === 0) return "On pace"
  return points + "% " + (difference < 0 ? "behind pace" : "ahead of pace")
}

function percent(value) {
  return Math.round(clamp(number(value, 0), 0, 1) * 100) + "%"
}

// Compact bar hover: "5h 42% · Weekly 31% · Monthly 18%"
function tooltipLimits(windows, nowMs) {
  if (!windows || typeof windows !== "object") return "OpenCode Go — no limits yet"
  var specs = [
    { key: "rolling", label: "5h" },
    { key: "weekly", label: "Weekly" },
    { key: "monthly", label: "Monthly" }
  ]
  var parts = []
  for (var i = 0; i < specs.length; i++) {
    var w = normalizeWindow(windows[specs[i].key], specs[i].key, nowMs)
    if (!w) continue
    parts.push(specs[i].label + " " + percent(w.percent))
  }
  if (!parts.length) return "OpenCode Go — no limits yet"
  return parts.join(" · ")
}

function countdown(resetMs, nowMs) {
  if (!resetMs || resetMs <= nowMs) return "now"
  var minutes = Math.max(0, Math.floor((resetMs - nowMs) / 60000))
  var days = Math.floor(minutes / 1440)
  var hours = Math.floor((minutes % 1440) / 60)
  var mins = minutes % 60
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + mins + "m"
  return mins + "m"
}

// ---- parsing -------------------------------------------------------------

function number(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function parseCollector(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object" || typeof parsed.status !== "string"
        || !Array.isArray(parsed.catalog)) {
      return { ok: false, error: "Could not parse OpenCode Go data" }
    }
    return {
      ok: true,
      data: {
        windows: parsed.windows && typeof parsed.windows === "object" ? parsed.windows : {},
        catalog: parsed.catalog,
        pricing: parsed.pricing && typeof parsed.pricing === "object" ? parsed.pricing : {},
        updatedAt: String(parsed.updatedAt || ""),
        error: String(parsed.error || "")
      }
    }
  } catch (error) {
    return { ok: false, error: "Could not parse OpenCode Go data" }
  }
}

// ---- formatting ----------------------------------------------------------

function tokenCount(value) {
  var amount = Math.max(0, number(value, 0))
  if (amount >= 1000000) return (amount / 1000000).toFixed(amount >= 100000000 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (amount >= 1000) return (amount / 1000).toFixed(amount >= 100000 ? 0 : 1).replace(/\.0$/, "") + "K"
  return String(Math.round(amount))
}

function money(value) {
  var amount = Math.max(0, number(value, 0))
  var text
  if (amount >= 100) text = amount.toFixed(0)
  else if (amount >= 1) text = amount.toFixed(2)
  else if (amount >= 0.01) text = amount.toFixed(3)
  else text = amount.toFixed(4)
  if (text.indexOf(".") >= 0) text = text.replace(/\.?0+$/, "")
  return "$" + (text === "" ? "0" : text)
}

function shortName(name) {
  var parts = String(name || "?").split("/")
  return parts[parts.length - 1] || "?"
}

// "zai-coding-plan" -> "zai", keeps plain names intact
function providerTag(provider) {
  return String(provider || "?").split("-")[0]
}

// ---- Go catalog: live pricing + computed quota picks -----------------------
// Typical agent turn (OpenCode Go docs, MiMo-V2.5 pattern). Used to estimate
// ~requests per 5h from current $/M: floor($12 rolling budget / cost/request).
var TYPICAL = { input: 830, cache: 71500, output: 295 }
var ROLLING_BUDGET_USD = 12

// Models excluded from automated picks (still listed in catalog).
var GO_EXCLUDE = {
  "muse-spark-1.2-contributor": "trains on prompts"
}

function requestCostUsd(live) {
  if (!live) return Infinity
  var cin = number(live.in, 0)
  var cout = number(live.out, 0)
  var ccache = number(live.cache, cin * 0.02)
  return (TYPICAL.input * cin + TYPICAL.cache * ccache + TYPICAL.output * cout) / 1e6
}

function estimateReq5h(live) {
  var cost = requestCostUsd(live)
  return cost > 0 && isFinite(cost) ? Math.floor(ROLLING_BUDGET_USD / cost) : 0
}

function pricePer1M(value) {
  var amount = number(value, -1)
  if (amount < 0) return "—"
  if (amount >= 1) return "$" + amount.toFixed(2) + "/M"
  if (amount >= 0.1) return "$" + amount.toFixed(2) + "/M"
  return "$" + amount.toFixed(3) + "/M"
}

function formatReq5h(value) {
  var n = number(value, 0)
  if (n <= 0) return "—"
  if (n >= 1000) return "~" + tokenCount(n) + " req/5h"
  return "~" + n + " req/5h"
}

function blendedCost(meta) {
  if (!meta) return Infinity
  return number(meta.in, Infinity) + number(meta.out, Infinity)
}

function catalogEntry(id, pricingMap, pickKind) {
  var key = String(id || "")
  var live = pricingMap && pricingMap[key] ? pricingMap[key] : null
  var hasPricing = !!(live && isFinite(number(live.in, NaN)) && isFinite(number(live.out, NaN)))
  return {
    id: key,
    displayName: key,
    inputPer1M: hasPricing ? number(live.in, -1) : -1,
    outputPer1M: hasPricing ? number(live.out, -1) : -1,
    requests5h: hasPricing ? estimateReq5h(live) : 0,
    pick: pickKind ? String(pickKind) : "",
    note: GO_EXCLUDE[key] ? String(GO_EXCLUDE[key]) : "",
    hasPricing: hasPricing,
    isOther: false
  }
}

function buildPickCandidates(ids, pricingMap) {
  var out = []
  var i, id, live, req, blended
  for (i = 0; i < (Array.isArray(ids) ? ids.length : 0); i++) {
    id = String(ids[i] || "")
    if (!id || GO_EXCLUDE[id]) continue
    live = pricingMap && pricingMap[id] ? pricingMap[id] : null
    if (!live || !isFinite(number(live.in, NaN)) || !isFinite(number(live.out, NaN))) continue
    req = estimateReq5h(live)
    if (req <= 0) continue
    blended = blendedCost(live)
    out.push({ id: id, requests5h: req, blended: blended, live: live })
  }
  return out
}

// Stretch quota = most ~req/5h at current prices. Best value = highest quota
// among capable mid-tier models (skip the single stretch winner).
function catalogPicks(ids, pricingMap) {
  var candidates = buildPickCandidates(ids, pricingMap)
  if (!candidates.length) return { volume: null, value: null }

  candidates.sort(function(a, b) {
    var q = number(b.requests5h, 0) - number(a.requests5h, 0)
    return q !== 0 ? q : String(a.id).localeCompare(String(b.id))
  })

  var volumeId = candidates[0].id
  var valueId = ""
  var bestReq = 0
  var i, entry
  for (i = 0; i < candidates.length; i++) {
    entry = candidates[i]
    if (entry.id === volumeId) continue
    if (number(entry.requests5h, 0) > bestReq) {
      bestReq = number(entry.requests5h, 0)
      valueId = entry.id
    }
  }
  if (!valueId && candidates.length > 1) valueId = candidates[1].id

  return {
    volume: catalogEntry(volumeId, pricingMap, "volume"),
    value: valueId ? catalogEntry(valueId, pricingMap, "value") : null
  }
}

function markPicks(entries, picks) {
  var volumeId = picks && picks.volume ? picks.volume.id : ""
  var valueId = picks && picks.value ? picks.value.id : ""
  var i, entry
  for (i = 0; i < entries.length; i++) {
    entry = entries[i]
    if (entry.isOther) continue
    if (entry.id === volumeId) entry.pick = "volume"
    else if (entry.id === valueId) entry.pick = "value"
    else entry.pick = ""
  }
  return entries
}

function sortCatalog(entries, sortBy) {
  var list = entries.slice()
  list.sort(function(a, b) {
    if (sortBy === "quota") {
      var q = number(b.requests5h, 0) - number(a.requests5h, 0)
      if (q !== 0) return q
    } else if (sortBy === "name") {
      var n = String(a.displayName).localeCompare(String(b.displayName))
      if (n !== 0) return n
    } else {
      var c = blendedCost({ in: a.inputPer1M, out: a.outputPer1M })
        - blendedCost({ in: b.inputPer1M, out: b.outputPer1M })
      if (c !== 0) return c
    }
    return String(a.displayName).localeCompare(String(b.displayName))
  })
  return list
}

function summarizeCatalog(ids, pricingMap, sortBy, maxN, picks) {
  var entries = []
  var i
  for (i = 0; i < (Array.isArray(ids) ? ids.length : 0); i++)
    entries.push(catalogEntry(ids[i], pricingMap, ""))
  markPicks(entries, picks || catalogPicks(ids, pricingMap))
  var sorted = sortCatalog(entries, sortBy)
  var limit = Math.max(1, maxN)
  var out = []
  var other = null
  for (i = 0; i < sorted.length; i++) {
    if (out.length < limit) out.push(sorted[i])
    else {
      if (!other) other = { displayName: "other (" + (sorted.length - limit) + ")", isOther: true, id: "", requests5h: 0, inputPer1M: -1, outputPer1M: -1, pick: "", note: "", hasPricing: false }
    }
  }
  if (other) out.push(other)
  return out
}

function pickLabel(pick) {
  if (pick === "volume") return "stretch quota"
  if (pick === "value") return "best value"
  return ""
}

var exportsObject = {
  ROLLING_MS: ROLLING_MS,
  WEEK_MS: WEEK_MS,
  MONTHLY_MS: MONTHLY_MS,
  windowMs: windowMs,
  normalizeWindow: normalizeWindow,
  expectedRemaining: expectedRemaining,
  behindPace: behindPace,
  paceText: paceText,
  percent: percent,
  countdown: countdown,
  parseCollector: parseCollector,
  tokenCount: tokenCount,
  money: money,
  pricePer1M: pricePer1M,
  formatReq5h: formatReq5h,
  shortName: shortName,
  providerTag: providerTag,
  summarizeCatalog: summarizeCatalog,
  catalogPicks: catalogPicks,
  pickLabel: pickLabel
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
