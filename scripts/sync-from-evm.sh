#!/usr/bin/env bash
set -euo pipefail
EVM_REPO="${1:-../sohopay-protocol}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$EVM_REPO/src" ]] || { echo "error: missing $EVM_REPO/src" >&2; exit 1; }
COMMIT="$(git -C "$EVM_REPO" rev-parse HEAD)"
mkdir -p "$ROOT/contracts"
rsync -a --delete "$EVM_REPO/src/" "$ROOT/contracts/"
rsync -a "$EVM_REPO/test/mocks/MockUSDTNonStandard.sol" "$ROOT/test/mocks/" 2>/dev/null || true
printf '# Commit: %s\n' "$COMMIT" > "$ROOT/SYNCED_FROM"
echo "Synced from $COMMIT"
