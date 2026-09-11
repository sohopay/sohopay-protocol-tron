#!/usr/bin/env bash
# Broadcast one settleAgentToAgent on Base Sepolia. Prints a real tx hash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${PATH}"

AMOUNT_USDC="${1:-20}"
DEPLOY_FILE="${A2A_DEPLOYMENT_FILE:-$ROOT/scripts/a2a/.deployment.json}"
ENV_FILE="${ENV_FILE:-$ROOT/.env.a2a.base-sepolia}"
NONCE_FILE="${A2A_NONCE_FILE:-${SOHOPAY_HOME:-$HOME}/.sohopay/a2a-nonce}"

[[ -f "$ENV_FILE" ]] || { echo "error: missing $ENV_FILE" >&2; exit 1; }
[[ -f "$DEPLOY_FILE" ]] || { echo "error: missing $DEPLOY_FILE — run the first live deploy first" >&2; exit 1; }

set -a && . "$ENV_FILE" && set +a
: "${BASE_SEPOLIA_RPC_URL:?}"
: "${DEPLOYER_PRIVATE_KEY:?}"
: "${BOB_AGENT_PRIVATE_KEY:?}"
: "${TRUSTED_SIGNER_PRIVATE_KEY:?}"

SETTLEMENT_ADDR="$(node -e 'const j=require(process.argv[1]); process.stdout.write(j.settlement)' "$DEPLOY_FILE")"
USDC_ADDR="$(node -e 'const j=require(process.argv[1]); process.stdout.write(j.usdc)' "$DEPLOY_FILE")"
mkdir -p "$(dirname "$NONCE_FILE")"
if [[ -f "$NONCE_FILE" ]]; then
  NONCE="$(tr -d '[:space:]' < "$NONCE_FILE")"
else
  NONCE="$(node -e 'const j=require(process.argv[1]); process.stdout.write(String(j.nextNonce||2))' "$DEPLOY_FILE")"
fi
export SETTLEMENT_ADDR USDC_ADDR
export A2A_NONCE="$NONCE"
export A2A_AMOUNT
A2A_AMOUNT="$(node -e 'process.stdout.write(String(Math.round(Number(process.argv[1])*1e6)))' "$AMOUNT_USDC")"

echo ">> live settle @phil $AMOUNT_USDC USDC nonce=$NONCE"
echo "   settlement $SETTLEMENT_ADDR"

FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-size}" forge script script/SettleBaseA2A.s.sol:SettleBaseA2A \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --chain 84532 \
  --broadcast \
  --slow \
  -vv

BROADCAST="$ROOT/broadcast/SettleBaseA2A.s.sol/84532/run-latest.json"
HASH="$(node --input-type=module -e '
  import { readFileSync } from "node:fs";
  const j = JSON.parse(readFileSync(process.argv[1], "utf8"));
  const txs = j.transactions || [];
  const hit = [...txs].reverse().find((t) => t.hash);
  if (!hit) process.exit(1);
  process.stdout.write(hit.hash);
' "$BROADCAST")"

echo "$((NONCE + 1))" > "$NONCE_FILE"

echo "A2A PAYMENT COMPLETE"
echo "TX_HASH=$HASH"
echo "BASESCAN=https://sepolia.basescan.org/tx/$HASH"
