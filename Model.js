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
        || !Array.isArray(parsed.models)) {
      return { ok: false, error: "Could not parse OpenCode usage" }
    }
    return {
      ok: true,
      data: {
        windows: parsed.windows && typeof parsed.windows === "object" ? parsed.windows : {},
        models: parsed.models,
        days: Array.isArray(parsed.days) ? parsed.days : [],
        totals: parsed.totals && typeof parsed.totals === "object"
          ? parsed.totals : { messages: 0, tokens: 0, cost: 0 },
        updatedAt: String(parsed.updatedAt || ""),
        error: String(parsed.error || "")
      }
    }
  } catch (error) {
    return { ok: false, error: "Could not parse OpenCode usage" }
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

// ---- sorting / summarising ----------------------------------------------

function cmpDesc(a, b) { return b - a }

function sortModels(models, sortBy) {
  var list = (Array.isArray(models) ? models : []).slice()
  list.sort(function(a, b) {
    var primary
    if (sortBy === "tokens") {
      primary = number(b.tokens ? b.tokens.total : 0, 0) - number(a.tokens ? a.tokens.total : 0, 0)
    } else if (sortBy === "messages") {
      primary = number(b.messages, 0) - number(a.messages, 0)
    } else {
      primary = number(b.cost, 0) - number(a.cost, 0)
    }
    if (primary !== 0) return primary
    // ties: more tokens first
    return number(b.tokens ? b.tokens.total : 0, 0) - number(a.tokens ? a.tokens.total : 0, 0)
  })
  return list
}

// Returns [{displayName, provider, model, messages, tokens, cost, isOther}]
// Top maxN entries individually; the tail folds into one "other" bucket.
function summarize(models, sortBy, maxN) {
  var sorted = sortModels(models, sortBy)
  var seen = {}
  var i, entry
  for (i = 0; i < sorted.length; i++) {
    entry = sorted[i]
    var base = shortName(entry.model)
    if (seen[base] !== undefined && seen[base] !== providerTag(entry.provider)) {
      entry.displayName = base + "@" + providerTag(entry.provider)
    } else {
      entry.displayName = base
      seen[base] = providerTag(entry.provider)
    }
  }
  var out = []
  var limit = Math.max(1, maxN)
  var other = null
  for (i = 0; i < sorted.length; i++) {
    entry = sorted[i]
    if (out.length < limit) {
      out.push(entry)
    } else {
      if (!other) {
        other = {
          displayName: "other",
          provider: "",
          model: "",
          messages: 0,
          tokens: { total: 0, input: 0, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0 },
          cost: 0,
          isOther: true
        }
      }
      other.messages += number(entry.messages, 0)
      other.tokens.total += number(entry.tokens ? entry.tokens.total : 0, 0)
      other.tokens.input += number(entry.tokens ? entry.tokens.input : 0, 0)
      other.tokens.output += number(entry.tokens ? entry.tokens.output : 0, 0)
      other.tokens.reasoning += number(entry.tokens ? entry.tokens.reasoning : 0, 0)
      other.tokens.cacheRead += number(entry.tokens ? entry.tokens.cacheRead : 0, 0)
      other.tokens.cacheWrite += number(entry.tokens ? entry.tokens.cacheWrite : 0, 0)
      other.cost += number(entry.cost, 0)
    }
  }
  if (other) out.push(other)
  return out
}

function maxTokenTotal(rows) {
  var peak = 0
  for (var i = 0; i < rows.length; i++) {
    var t = rows[i].isOther ? rows[i].tokens.total : number(rows[i].tokens.total, 0)
    peak = Math.max(peak, t)
  }
  return peak
}

// ---- sparkline -----------------------------------------------------------

function dayTokens(day) { return Math.max(0, number(day && day.tokens, 0)) }

function recentPeak(days) {
  var list = Array.isArray(days) ? days : []
  var peak = 0
  for (var i = 0; i < list.length; i++) peak = Math.max(peak, dayTokens(list[i]))
  return peak
}

function dayLabel(value) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""))
  if (!match) return "—"
  var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
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
  shortName: shortName,
  providerTag: providerTag,
  sortModels: sortModels,
  summarize: summarize,
  maxTokenTotal: maxTokenTotal,
  dayTokens: dayTokens,
  recentPeak: recentPeak,
  dayLabel: dayLabel
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
