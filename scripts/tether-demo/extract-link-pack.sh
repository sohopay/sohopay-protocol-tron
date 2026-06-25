#!/usr/bin/env bash
# Generate docs/tether-demo/LINK-PACK.md from Foundry broadcast artifacts (chain 9746).
# Pulls deployed contract addresses + act tx hashes and renders Plasmascan links.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null || { echo "error: jq required" >&2; exit 1; }

EXPLORER="https://testnet.plasmascan.to"
OUT="docs/tether-demo/LINK-PACK.md"
SHA="$(sed -n 's/^# Commit: //p' SYNCED_FROM 2>/dev/null || echo unknown)"

# newest broadcast for the demo (fall back to the prod deploy)
BC="$(ls -t broadcast/DemoPlasma.s.sol/9746/run-latest.json broadcast/Deploy.s.sol/9746/run-latest.json 2>/dev/null | head -1 || true)"
[[ -n "${BC:-}" && -f "$BC" ]] || { echo "error: no broadcast artifact under broadcast/*/9746/" >&2; exit 1; }

addr_of() { jq -r --arg n "$1" '[.transactions[] | select(.contractName==$n) | .contractAddress] | last // "—"' "$BC"; }

{
  echo "# SOHOPay Plasma Demo — LINK-PACK"
  echo ""
  echo "Network: Plasma testnet (chain 9746) · Explorer: $EXPLORER"
  echo "Vendored \`sohopay-protocol\` commit: \`$SHA\`"
  echo ""
  echo "| Item | Address / Tx |"
  echo "|------|--------------|"
  for pair in "USDT (MockUSDT):MockUSDT" \
              "Settlement proxy:ERC1967Proxy" \
              "Vault proxy:SohoVault" \
              "TreasuryController:SohoTreasuryController"; do
    label="${pair%%:*}"; name="${pair##*:}"; a="$(addr_of "$name")"
    echo "| $label | [$a]($EXPLORER/address/$a) |"
  done
  # Act 3 settle + Act 5 emergencyRedeem tx hashes (by function selector / order)
  SETTLE="$(jq -r '[.transactions[] | select(.function!=null and (.function|test("settleWithAttestation"))) | .hash] | last // "—"' "$BC")"
  EMERG="$(jq -r '[.transactions[] | select(.function!=null and (.function|test("emergencyRedeem"))) | .hash] | last // "—"' "$BC")"
  echo "| Act 3 settle tx | [$SETTLE]($EXPLORER/tx/$SETTLE) |"
  echo "| Act 5 emergencyRedeem tx | [$EMERG]($EXPLORER/tx/$EMERG) |"
} > "$OUT"

echo "wrote $OUT"
