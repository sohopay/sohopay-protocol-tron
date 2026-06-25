#!/usr/bin/env bash
# Print Plasmascan verification links for the latest Plasma Testnet (chain 9746) deploy.
# Lightweight companion to extract-link-pack.sh — prints to stdout, writes nothing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null || { echo "error: jq required" >&2; exit 1; }

# explorer mapping by chain id
chain_explorer() { case "$1" in 9746) echo "https://testnet.plasmascan.to" ;; 9745) echo "https://plasmascan.to" ;; *) echo "" ;; esac; }
CHAIN="${CHAIN_ID:-9746}"
EXPLORER="$(chain_explorer "$CHAIN")"
[[ -n "$EXPLORER" ]] || { echo "error: no explorer mapping for chain $CHAIN" >&2; exit 1; }

BC="$(ls -t broadcast/*/"$CHAIN"/run-latest.json 2>/dev/null | head -1 || true)"
[[ -n "${BC:-}" && -f "$BC" ]] || { echo "error: no broadcast under broadcast/*/$CHAIN/ — deploy first" >&2; exit 1; }

echo "Plasma chain $CHAIN → $EXPLORER"
jq -r --arg e "$EXPLORER" '
  .transactions[]
  | select(.contractAddress != null)
  | "  \(.contractName // "contract")  \($e)/address/\(.contractAddress)"
' "$BC"
jq -r --arg e "$EXPLORER" '
  .transactions[]
  | select(.hash != null and .function != null)
  | "  tx \(.function)  \($e)/tx/\(.hash)"
' "$BC"
