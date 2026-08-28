# omarchy-opencode-usage

Compact Omarchy bar widget for local OpenCode usage — per-model tokens, cost
ranking, and a day sparkline, read straight from `~/.local/share/opencode/opencode.db`
(no network). OpenCode Go limit windows are out of scope here; this widget is
about *what you actually used and what it cost*.

Bar pill shows the 7-day cost; the popout shows totals, sparkline, and every
model sorted by cost / tokens / messages.

Inspired by [local.opencode-go](https://omarchyplugins.com/plugin.html?id=local.opencode-go)
(limit windows) and Claudebar (per-model breakdown).

## Install

```bash
./install.sh
omarchy plugin enable local.opencode-usage
```

## Files

| File | Role |
| --- | --- |
| `collector.sh` | sqlite3 → JSON rollup (models, days, totals) |
| `Model.js` | parsing + sorting + formatting (pure JS) |
| `Service.qml` | process runner on a refresh timer |
| `Panel.qml` | bar pill + compact popout |

## Settings (Omarchy Settings → Widgets)

- `refreshIntervalSec` 60–3600 (default 300) — collector re-run interval
- `windowDays` 1–30 (default 7) — history window
- `maxModels` 3–15 (default 8) — model rows before folding into "other"
- `sortBy` cost / tokens / messages (default cost)
