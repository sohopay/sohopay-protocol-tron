#!/usr/bin/env bash
# Create a gitignored Base Sepolia env with throwaway keys + public RPC.
# Does not broadcast. Does not print private keys.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.foundry/bin:${PATH}"

DEST="${1:-.env.a2a.base-sepolia}"
if [[ -f "$DEST" ]]; then
  echo "Already exists: $DEST (not overwriting)"
else
  command -v cast >/dev/null || { echo "error: foundry cast not installed" >&2; exit 1; }

  new_key() {
    cast wallet new --json | node -e '
      let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
        const j=JSON.parse(s);
        const k=j.private_key||j.privateKey||j.key;
        if(!k) throw new Error("cast wallet new --json missing private_key");
        process.stdout.write(k.startsWith("0x")?k:"0x"+k);
      });
    '
  }

  DEPLOYER_PRIVATE_KEY="$(new_key)"
  BOB_AGENT_PRIVATE_KEY="$(new_key)"
  TRUSTED_SIGNER_PRIVATE_KEY="$(new_key)"
  PHIL_AGENT_PRIVATE_KEY="$(new_key)"
  PHIL_RECEIVE_KEY="$(new_key)"
  BOB_RECEIVE_KEY="$(new_key)"

  PHIL_RECEIVE_ADDRESS="$(cast wallet address --private-key "$PHIL_RECEIVE_KEY")"
  BOB_RECEIVE_ADDRESS="$(cast wallet address --private-key "$BOB_RECEIVE_KEY")"

  cat > "$DEST" <<EOF
# Gitignored throwaway Base Sepolia demo keys. Not for mainnet or real funds.
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=
USDC_ADDR=
EXPECTED_CHAIN_ID=84532
USE_MOCK_USDC=1

DEPLOYER_PRIVATE_KEY=${DEPLOYER_PRIVATE_KEY}
BOB_AGENT_PRIVATE_KEY=${BOB_AGENT_PRIVATE_KEY}
TRUSTED_SIGNER_PRIVATE_KEY=${TRUSTED_SIGNER_PRIVATE_KEY}
PHIL_AGENT_PRIVATE_KEY=${PHIL_AGENT_PRIVATE_KEY}

PHIL_RECEIVE_ADDRESS=${PHIL_RECEIVE_ADDRESS}
BOB_RECEIVE_ADDRESS=${BOB_RECEIVE_ADDRESS}
EOF
  chmod 600 "$DEST"
  echo "Wrote $DEST"
fi

set -a && . "./$DEST" && set +a
DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
echo
echo "Deployer (fund with Base Sepolia ETH):"
echo "  $DEPLOYER_ADDR"
echo "Phil receive (will show +20 demo USDC after settle):"
echo "  $PHIL_RECEIVE_ADDRESS"
echo
echo "Faucets:"
echo "  https://www.alchemy.com/faucets/base-sepolia"
echo "  https://portal.cdp.coinbase.com/products/faucet"
echo
echo "Then:"
echo "  NETWORK=base-sepolia USE_MOCK_USDC=1 ./scripts/a2a/run-base-a2a-demo.sh"
