#!/usr/bin/env bash
# Production-style deploy of the SOHOPay stack to Plasma Testnet (chain 9746) using the
# vendored, audited script/Deploy.s.sol. For the self-contained 5-act demo use
# run-plasma-demo.sh instead (this script is the realistic timelocked path).
#
#   ENV_FILE=.env.usdt-demo.plasma ./scripts/tether-demo/deploy-plasma-testnet.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
ENV_FILE="${ENV_FILE:-.env}"
[[ -f "$ENV_FILE" ]] && set -a && . "./$ENV_FILE" && set +a

: "${PLASMA_RPC:?set PLASMA_RPC}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${USDC_ADDR:?set USDC_ADDR (settlement asset) — for a mock asset, use run-plasma-demo.sh}"
command -v cast >/dev/null || { echo "error: Foundry (cast) not installed — https://getfoundry.sh" >&2; exit 1; }

# XPL gas balance check (Plasma gas token is XPL, not ETH).
DEPLOYER="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
BAL_WEI="$(cast balance "$DEPLOYER" --rpc-url "$PLASMA_RPC")"
echo "Deployer $DEPLOYER — balance: $(cast from-wei "$BAL_WEI") XPL"
if [[ "$BAL_WEI" == "0" ]]; then
  echo "error: deployer has 0 XPL — fund it from a Plasma testnet faucet (gas.zip / Chainlink / QuickNode)" >&2
  exit 1
fi

echo "Deploying to Plasma Testnet (chain ${EXPECTED_CHAIN_ID:-9746}) via $PLASMA_RPC"
forge script script/Deploy.s.sol:Deploy \
  --rpc-url plasma_testnet \
  --broadcast \
  --slow \
  ${PLASMASCAN_API_KEY:+--verify --verifier blockscout --verifier-url https://testnet.plasmascan.to/api} \
  -vvv

echo ">> regenerating link pack"
"$ROOT/scripts/tether-demo/extract-link-pack.sh" || true
