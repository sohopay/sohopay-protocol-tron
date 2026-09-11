#!/usr/bin/env bash
# One-command SOHOPay A2A demo: "Pay Phil's agent $20" on Base Sepolia (chain 84532).
# Default: in-memory isolated deploy + MockUSDC (prints A2A PAYMENT COMPLETE).
# Real testnet: NETWORK=base-sepolia ./scripts/a2a/run-base-a2a-demo.sh
#
# Experimental — A2A is not covered by the prior v1 audit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${PATH}"

NETWORK="${NETWORK:-local}"
ENV_FILE="${ENV_FILE:-}"
if [[ -z "$ENV_FILE" ]]; then
  if [[ "$NETWORK" == "base-sepolia" && -f .env.a2a.base-sepolia ]]; then
    ENV_FILE=.env.a2a.base-sepolia
  elif [[ -f .env ]]; then
    ENV_FILE=.env
  fi
fi
if [[ -n "${ENV_FILE}" && -f "$ENV_FILE" ]]; then
  set -a && . "./$ENV_FILE" && set +a
fi

command -v forge >/dev/null || { echo "error: Foundry (forge) not installed — https://getfoundry.sh" >&2; exit 1; }

if [[ ! -f lib/forge-std/src/Script.sol ]]; then
  echo ">> installing pinned dependencies"
  forge install || git submodule update --init --recursive
fi

# Local anvil defaults (throwaway). Never used as production keys.
: "${DEPLOYER_PRIVATE_KEY:=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
: "${BOB_AGENT_PRIVATE_KEY:=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
: "${TRUSTED_SIGNER_PRIVATE_KEY:=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a}"
export DEPLOYER_PRIVATE_KEY BOB_AGENT_PRIVATE_KEY TRUSTED_SIGNER_PRIVATE_KEY
export EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-84532}"

echo ">> forge build"
forge build

print_basescan() {
  local broadcast="$ROOT/broadcast/DemoBaseA2A.s.sol/84532/run-latest.json"
  if [[ ! -f "$broadcast" ]]; then
    echo "No broadcast file at $broadcast — not claiming an explorer link."
    return 1
  fi
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const j = JSON.parse(readFileSync(process.argv[1], "utf8"));
    const txs = [...(j.transactions || []), ...(j.receipts || [])];
    const hashes = [];
    for (const t of txs) {
      const fn = String(t.function || t.transactionType || "");
      const hash = t.hash || t.transactionHash;
      if (hash && /settleAgentToAgent/i.test(fn)) hashes.push(hash);
    }
    if (!hashes.length) {
      for (const t of txs) {
        const hash = t.hash || t.transactionHash;
        if (hash) hashes.push(hash);
      }
    }
    const unique = [...new Set(hashes)];
    if (!unique.length) {
      console.error("Broadcast JSON has no transaction hashes.");
      process.exit(1);
    }
    const settle = unique.find((_, i) => /settleAgentToAgent/i.test(String((j.transactions || [])[i]?.function || ""))) || unique[unique.length - 1];
    console.log("====================================================");
    console.log("BASESCAN (Base Sepolia)");
    console.log("====================================================");
    console.log("Settle tx:     https://sepolia.basescan.org/tx/" + settle);
    console.log("All txs:");
    for (const h of unique) console.log("  https://sepolia.basescan.org/tx/" + h);
  ' "$broadcast"
}

if [[ "$NETWORK" == "base-sepolia" ]]; then
  : "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL for NETWORK=base-sepolia}"
  : "${PHIL_RECEIVE_ADDRESS:?set PHIL_RECEIVE_ADDRESS}"

  USE_MOCK_USDC="${USE_MOCK_USDC:-0}"
  if [[ "$USE_MOCK_USDC" == "1" || -z "${USDC_ADDR:-}" ]]; then
    unset USDC_ADDR || true
    export USE_MOCK_USDC=1
    echo ">> live Base Sepolia will deploy MockUSDC (explorer-visible demo token, not Circle USDC)"
  elif [[ "${USDC_ADDR}" != "0x036CbD53842c5426634e7929541eC2318f3dCF7e" ]]; then
    echo "error: USDC_ADDR must be official Base Sepolia USDC 0x036CbD53842c5426634e7929541eC2318f3dCF7e or empty (MockUSDC)" >&2
    exit 1
  fi

  CHAIN_ID="$(cast chain-id --rpc-url "$BASE_SEPOLIA_RPC_URL")"
  if [[ "$CHAIN_ID" != "84532" ]]; then
    echo "error: RPC chain id is $CHAIN_ID, expected 84532" >&2
    exit 1
  fi

  DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
  ETH_BAL="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
  echo ">> Base Sepolia preflight"
  echo "   chain id:     $CHAIN_ID"
  echo "   USDC:         ${USDC_ADDR:-MockUSDC (will deploy)}"
  echo "   deployer:     $DEPLOYER_ADDR"
  echo "   ETH (wei):    $ETH_BAL"
  echo "   Phil receive: $PHIL_RECEIVE_ADDRESS"

  if [[ "$ETH_BAL" == "0" ]]; then
    echo "READY FOR BASE SEPOLIA EXECUTION"
    echo "Missing: deployer Base Sepolia ETH for gas"
    echo "Fund this address, then re-run:"
    echo "  $DEPLOYER_ADDR"
    echo "Faucet: https://www.alchemy.com/faucets/base-sepolia"
    echo "        https://portal.cdp.coinbase.com/products/faucet"
    exit 2
  fi
  if [[ -n "${USDC_ADDR:-}" ]]; then
    USDC_BAL="$(cast call "$USDC_ADDR" "balanceOf(address)(uint256)" "$DEPLOYER_ADDR" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
    echo "   USDC (raw):   $USDC_BAL"
    if [[ "$USDC_BAL" == "0" ]]; then
      echo "READY FOR BASE SEPOLIA EXECUTION"
      echo "Missing: test USDC at $USDC_ADDR for vault/hot-float liquidity"
      echo "Or re-run with USE_MOCK_USDC=1 to deploy a mintable demo token on-chain."
      exit 2
    fi
  fi

  echo ">> broadcasting isolated A2A deploy + 20 USDC settle on Base Sepolia"
  export SKIP_A2A_BLOCKED_ACT=true
  # Size profile keeps SohoSettlement under the 24KB EIP-170 limit (A2A additions
  # push the default optimizer_runs=10000 artifact over 24576).
  FOUNDRY_PROFILE=size forge script script/DemoBaseA2A.s.sol:DemoBaseA2A \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" \
    --chain 84532 \
    --broadcast \
    --slow \
    -vv

  print_basescan
else
  echo ">> running isolated A2A demo in-memory at chain 84532 (MockUSDC)"
  unset USDC_ADDR || true
  forge script script/DemoBaseA2A.s.sol:DemoBaseA2A --chain 84532 -vv
fi
