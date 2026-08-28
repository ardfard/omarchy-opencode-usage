#!/usr/bin/env bash
# Sync the plugin into ~/.config/omarchy/plugins/ (dir name MUST equal manifest id).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.config/omarchy/plugins/local.opencode-usage"

echo "==> Copying $SRC_DIR → $DEST_DIR"
mkdir -p "$DEST_DIR"
cp -a "$SRC_DIR"/. "$DEST_DIR"/
rm -rf "$DEST_DIR/.git" "$DEST_DIR/.jj"
find "$DEST_DIR" -name '.jj' -maxdepth 2 2>/dev/null | xargs -r rm -rf

if command -v omarchy >/dev/null 2>&1; then
  echo "==> Validating"
  omarchy plugin validate "$DEST_DIR"
fi

if command -v qmllint >/dev/null 2>&1; then
  SHELL_PATH="${OMARCHY_SHELL_PATH:-/usr/share/omarchy/shell}"
  echo "==> qmllint"
  for f in Panel.qml Service.qml; do
    qmllint -I "$SHELL_PATH" "$DEST_DIR/$f" && echo "   $f OK"
  done
  qmllint "$DEST_DIR/Model.js" >/dev/null 2>&1 || true # .pragma library trips plain JS parse; skipped
fi

# rescanPlugins only picks up added/removed plugins; a bar widget the shell has
# already constructed keeps its old QML until the process restarts.
echo "==> Restart shell"
omarchy restart shell

echo "Done."
