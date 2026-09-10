#!/usr/bin/env bash
# Install the `sohopay` command so a new terminal can type: sohopay
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/bin/sohopay"
DEST_DIR="${SOHOPAY_BIN_DIR:-$HOME/.local/bin}"
DEST="$DEST_DIR/sohopay"

[[ -x "$SRC" ]] || chmod +x "$SRC" "$ROOT/scripts/a2a/sohopay-terminal.sh" "$ROOT/scripts/a2a/pay-agent.mjs"
mkdir -p "$DEST_DIR"
ln -sfn "$SRC" "$DEST"
chmod +x "$DEST"

echo "Installed: $DEST → $SRC"
if command -v sohopay >/dev/null 2>&1; then
  echo "Ready. Open a terminal and type:  sohopay"
else
  echo
  echo "Add this to your ~/.zshrc (then run: source ~/.zshrc):"
  echo "  export PATH=\"$DEST_DIR:\$PATH\""
  echo
  echo "Or run once in this shell:"
  echo "  export PATH=\"$DEST_DIR:\$PATH\""
  echo "  sohopay"
fi
