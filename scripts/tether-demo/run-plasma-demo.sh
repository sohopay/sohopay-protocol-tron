#!/usr/bin/env bash
# One-command SOHOPay 5-act USDT demo on Plasma testnet (chain 9746).
# Deploys the audited stack + a mock 6-dec USDT (unless USDC_ADDR is set), then runs
# Acts 1-5 and prints "DEMO COMPLETE". Demo only — see DemoPlasma.s.sol header.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && . ./.env && set +a

: "${PLASMA_RPC:?set PLASMA_RPC}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${AGENT_PRIVATE_KEY:?set AGENT_PRIVATE_KEY}"
: "${TRUSTED_SIGNER_PRIVATE_KEY:?set TRUSTED_SIGNER_PRIVATE_KEY}"

command -v forge >/dev/null || { echo "error: Foundry (forge) not installed — https://getfoundry.sh" >&2; exit 1; }
[[ -d lib/forge-std ]] || forge install foundry-rs/forge-std \
  OpenZeppelin/openzeppelin-contracts OpenZeppelin/openzeppelin-contracts-upgradeable

echo ">> forge build"
forge build

echo ">> running 5-act demo on Plasma testnet"
forge script script/DemoPlasma.s.sol:DemoPlasma \
  --rpc-url plasma_testnet \
  --broadcast \
  --slow \
  -vvv

echo ">> generating LINK-PACK"
"$ROOT/scripts/tether-demo/extract-link-pack.sh" || true
