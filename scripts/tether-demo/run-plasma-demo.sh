#!/usr/bin/env bash
# One-command SOHOPay 5-act USDT demo on Plasma (chain 9746).
# Runs the full audited stack + a mock 6-dec USDT through Acts 1-5 and prints
# "DEMO COMPLETE". Demo only — see DemoPlasma.s.sol header.
#
# This runs the 5 acts in-memory at chain id 9746 (the protocol's 48h-style timelock
# means schedule+execute+settle cannot share one live broadcast — see DemoPlasma.s.sol
# and Deploy.s.sol). For a persistent on-chain testnet deployment with Plasmascan links,
# use deploy-plasma.sh (production two-leg schedule/execute).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && . ./.env && set +a

: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${AGENT_PRIVATE_KEY:?set AGENT_PRIVATE_KEY}"
: "${TRUSTED_SIGNER_PRIVATE_KEY:?set TRUSTED_SIGNER_PRIVATE_KEY}"

command -v forge >/dev/null || { echo "error: Foundry (forge) not installed — https://getfoundry.sh" >&2; exit 1; }

# Reproducible deps: pinned in foundry.lock (audited OZ commits). forge install reads the
# lockfile; fall back to submodule checkout. NEVER install unpinned — OZ >= 5.6 won't compile.
if [[ ! -f lib/forge-std/src/Script.sol ]]; then
  echo ">> installing pinned dependencies"
  forge install || git submodule update --init --recursive
fi

echo ">> forge build"
forge build

echo ">> running 5-act demo at chain 9746"
forge script script/DemoPlasma.s.sol:DemoPlasma --chain 9746 -vv

echo ">> (optional) for on-chain deploy + LINK-PACK, run scripts/tether-demo/deploy-plasma.sh"
