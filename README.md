# omarchy-opencode-go-usage

Omarchy bar widget for **[OpenCode Go](https://opencode.ai/docs/go/)**. Works with any
agent (OpenCode, pi, hermes, omp, etc.) that uses your Go API key.

It shows:

- **Go limit windows** — rolling 5h ($12), weekly ($30) and monthly ($60)
  from `GET /zen/go/v1/usage`, with progress bars, reset countdowns and
  behind-pace highlighting.
- **Model catalog** — live list from `GET /zen/go/v1/models`, **current** $/M from
  [models.dev](https://models.dev) (includes promos), sorted by cost, quota, or name.
- **Picks** — computed daily from live pricing: stretch quota (most ~req/5h)
  and best value (top quota after excluding the stretch winner). Muse Spark
  excluded (trains on prompts).

The bar is an icon pill. Hover for limit %. Click for the full panel.

Inspired by [local.opencode-go](https://omarchyplugins.com/plugin.html?id=local.opencode-go).

## Install

```bash
git clone https://github.com/ardfard/omarchy-opencode-usage.git
cd omarchy-opencode-usage
./install.sh
omarchy plugin enable local.opencode-go-usage
```

Put your Go key in `~/.local/share/opencode/auth.json` under `opencode-go`
(OpenCode TUI: `/connect` → OpenCode Go). Other agents use the same key against
`https://opencode.ai/zen/go/v1`.

## Remove

```bash
omarchy plugin disable local.opencode-go-usage
omarchy plugin remove local.opencode-go-usage
rm -rf ~/.config/omarchy/plugins/local.opencode-go-usage
omarchy shell shell rescanPlugins
```

## Dependencies

- `curl` — Go limits, catalog, and models.dev pricing fetch
- `jq` — JSON assembly

Limits need an `opencode-go` key. Catalog and pricing fetches are public.

## How prices update

On each refresh (default hourly), `collector.sh`:

1. Fetches model IDs from `https://opencode.ai/zen/go/v1/models`
2. Fetches **current** input/output $/1M from `https://models.dev/api.json`
   under `opencode-go` (this tracks promos, e.g. GLM-5.3-Flash at $0.075/$0.25)

There is no pricing field on the Go API itself. models.dev is maintained by the
OpenCode team and updates when rates change.

**Stretch quota / best value picks** recompute at most once per day from current
pricing: estimate ~req/5h as `$12 rolling budget ÷ cost per typical agent turn`
(830 input + 71.5K cached + 295 output tokens). Stretch = highest quota among
eligible models; best value = next highest (Muse Spark excluded). Limits and
catalog prices still refresh hourly.

## Settings (Omarchy Settings → Widgets)

- `refreshIntervalSec` 60–3600 (default 3600, hourly)
- `maxModels` 3–30 (default 12) — catalog rows before folding into "other"
- `sortBy` cost / quota / name (default cost)

## License

MIT — see [LICENSE](LICENSE).
