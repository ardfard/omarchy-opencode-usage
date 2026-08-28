# omarchy-opencode-usage

Compact Omarchy bar widget for OpenCode usage. It combines:

- **Local usage** — per-model tokens and cost, a day-by-day sparkline and
  totals, read straight from `~/.local/share/opencode/opencode.db` (fast,
  offline).
- **OpenCode Go limit windows** — the rolling 5h, weekly and monthly
  subscription limits from the OpenCode Go usage API, with progress bars,
  reset countdowns and behind-pace highlighting.

The bar shows an icon-only pill; the popout shows limits, totals, the
sparkline and every model sorted by cost / tokens / messages.

Inspired by [local.opencode-go](https://omarchyplugins.com/plugin.html?id=local.opencode-go)
(limit windows) and Claudebar (per-model breakdown).

## Install

```bash
git clone https://github.com/ardfard/omarchy-opencode-usage.git
cd omarchy-opencode-usage
./install.sh
omarchy plugin enable local.opencode-usage
```

`install.sh` copies the plugin to `~/.config/omarchy/plugins/local.opencode-usage/`,
validates the manifest and rescans the shell.

## Remove

```bash
omarchy plugin disable local.opencode-usage
omarchy plugin remove local.opencode-usage
# or, if the command above is unavailable on your Omarchy version:
rm -rf ~/.config/omarchy/plugins/local.opencode-usage
omarchy shell shell rescanPlugins
```

## Dependencies

- `sqlite3` (with JSON functions, 3.53+) — reads the local OpenCode DB
- `jq` — collector JSON assembly
- `curl` — OpenCode Go limit fetch (optional; the widget degrades to local-only
  data without an `opencode-go` key in `~/.local/share/opencode/auth.json`)

## Settings (Omarchy Settings → Widgets)

- `refreshIntervalSec` 60–3600 (default 300) — collector re-run interval
- `windowDays` 1–30 (default 7) — history window
- `maxModels` 3–15 (default 8) — model rows before folding into "other"
- `sortBy` cost / tokens / messages (default cost)

## License

MIT — see [LICENSE](LICENSE).
