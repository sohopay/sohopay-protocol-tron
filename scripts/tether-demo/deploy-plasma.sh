#!/usr/bin/env bash
# Production-style deploy of the SOHOPay stack to Plasma testnet (chain 9746) using the
# vendored, audited script/Deploy.s.sol. For the self-contained 5-act demo use
# run-plasma-demo.sh instead (this script is the realistic timelocked path).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && . ./.env && set +a

: "${PLASMA_RPC:?set PLASMA_RPC}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${USDC_ADDR:?set USDC_ADDR (settlement asset) — deploy a MockUSDT first if needed}"

echo "Deploying to Plasma testnet (chain ${EXPECTED_CHAIN_ID:-9746}) via $PLASMA_RPC"
forge script script/Deploy.s.sol:Deploy \
  --rpc-url plasma_testnet \
  --broadcast \
  --slow \
  ${PLASMASCAN_API_KEY:+--verify --verifier blockscout --verifier-url https://testnet.plasmascan.to/api} \
  -vvv
