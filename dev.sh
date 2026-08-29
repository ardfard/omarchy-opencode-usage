#!/usr/bin/env bash
# Symlink this checkout into the Omarchy plugin dir and follow shell logs.
# Edit QML here; saves reload via inotify. Use ./install.sh for a real copy.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.config/omarchy/plugins/local.opencode-go-usage"
PLUGIN_ID="local.opencode-go-usage"

usage() {
  cat <<'EOF'
Usage: ./dev.sh [--no-tail] [--restart]

  Symlink the repo into ~/.config/omarchy/plugins/local.opencode-go-usage,
  validate, enable, rescan (or restart), then follow omarchy-shell logs.

  --no-tail   Link + enable only; do not journalctl -f
  --restart   Full shell restart instead of rescanPlugins
EOF
}

NO_TAIL=0
RESTART=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --no-tail) NO_TAIL=1 ;;
    --restart) RESTART=1 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$DEST_DIR")"

if [[ -L "$DEST_DIR" ]]; then
  current="$(readlink -f "$DEST_DIR" || true)"
  if [[ "$current" == "$SRC_DIR" ]]; then
    echo "==> Already linked: $DEST_DIR → $SRC_DIR"
  else
    echo "==> Relinking $DEST_DIR → $SRC_DIR (was → $current)"
    ln -sfn "$SRC_DIR" "$DEST_DIR"
  fi
elif [[ -e "$DEST_DIR" ]]; then
  echo "==> Replacing copied install at $DEST_DIR with symlink"
  rm -rf "$DEST_DIR"
  ln -sfn "$SRC_DIR" "$DEST_DIR"
else
  echo "==> Linking $DEST_DIR → $SRC_DIR"
  ln -sfn "$SRC_DIR" "$DEST_DIR"
fi

if command -v omarchy >/dev/null 2>&1; then
  echo "==> Validating"
  omarchy plugin validate "$DEST_DIR"

  echo "==> Enabling $PLUGIN_ID"
  omarchy plugin enable "$PLUGIN_ID" 2>/dev/null || true
fi

if command -v qmllint >/dev/null 2>&1; then
  SHELL_PATH="${OMARCHY_SHELL_PATH:-/usr/share/omarchy/shell}"
  echo "==> qmllint"
  for f in Panel.qml Service.qml; do
    if [[ -f "$SRC_DIR/$f" ]]; then
      qmllint -I "$SHELL_PATH" "$SRC_DIR/$f" && echo "   $f OK"
    fi
  done
fi

if [[ "$RESTART" -eq 1 ]]; then
  echo "==> Restart shell"
  omarchy restart shell
else
  echo "==> Rescan plugins"
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins
  else
    echo "    omarchy-shell not on PATH; falling back to restart"
    omarchy restart shell
  fi
fi

echo
echo "Edit files in $SRC_DIR — saves hot-reload."
echo "Force reload: omarchy-shell shell rescanPlugins"
echo "Full restart: ./dev.sh --restart   or   omarchy restart shell"
echo

if [[ "$NO_TAIL" -eq 1 ]]; then
  echo "Done (no journal follow)."
  exit 0
fi

echo "==> journalctl -t omarchy-shell -f  (Ctrl-C to stop)"
exec journalctl --user -t omarchy-shell -f --no-hostname
