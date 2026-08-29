# omarchy-opencode-usage

Omarchy bar widget for **[OpenCode Go](https://opencode.ai/docs/go/)** usage.
Not general OpenCode traffic. Other providers in `opencode.db` are ignored.

It shows:

- **Go limit windows** — rolling 5h ($12), weekly ($30) and monthly ($60)
  from the Go usage API, with progress bars, reset countdowns and behind-pace
  highlighting.
- **Local Go usage** — per-model tokens and cost plus a day sparkline, from
  `providerID = opencode-go` rows in `~/.local/share/opencode/opencode.db`.

The bar is an icon pill. The popout has limits, totals, the sparkline and
models sorted by cost / tokens / messages.

Inspired by [local.opencode-go](https://omarchyplugins.com/plugin.html?id=local.opencode-go)
(limit windows) and Claudebar (per-model breakdown).

## Best value model (Go)

Go limits are dollar-based, so cheaper models buy you more requests. Per the
[official Go docs](https://opencode.ai/docs/go/), **MiMo-V2.5**
(`opencode-go/mimo-v2.5`) is the high-volume pick: roughly 30k requests per
5h window at $0.14 / $0.28 per 1M tokens, with the full $60 monthly usage
bucket.

Use something sharper (DeepSeek V4 Flash, Qwen3.8 Flash, GLM-5.3-Flash, …)
when you need more capability. Those burn the same $12 / $30 / $60 caps
faster. Muse Spark 1.2 Contributor is even cheaper on quota but is
region-limited and trains on your prompts.

Model list and quotas change. Check the docs before locking a default.

## Install

```bash
git clone https://github.com/ardfard/omarchy-opencode-usage.git
cd omarchy-opencode-usage
./install.sh
omarchy plugin enable local.opencode-go-usage
```

`install.sh` copies the plugin to `~/.config/omarchy/plugins/local.opencode-go-usage/`,
validates the manifest and rescans the shell.

You need an OpenCode Go subscription and `/connect` → OpenCode Go in the TUI
so `~/.local/share/opencode/auth.json` has an `opencode-go` key.

## Remove

```bash
omarchy plugin disable local.opencode-go-usage
omarchy plugin remove local.opencode-go-usage
# or, if the command above is unavailable on your Omarchy version:
rm -rf ~/.config/omarchy/plugins/local.opencode-go-usage
omarchy shell shell rescanPlugins
```

## Dependencies

- `sqlite3` (with JSON functions, 3.53+) — reads `opencode-go` rows from the local DB
- `jq` — collector JSON assembly
- `curl` — Go limit fetch (optional; without an `opencode-go` key the widget
  still shows local Go model stats, with empty limit windows)

## Settings (Omarchy Settings → Widgets)

- `refreshIntervalSec` 60–3600 (default 300) — collector re-run interval
- `windowDays` 1–30 (default 7) — history window
- `maxModels` 3–15 (default 8) — model rows before folding into "other"
- `sortBy` cost / tokens / messages (default cost)

## License

MIT — see [LICENSE](LICENSE).
