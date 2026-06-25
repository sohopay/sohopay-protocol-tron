# CEO Runbook — SOHOPay USDT Demo on Plasma

Run the full 5-act demo with **one command**. No Solidity knowledge required.

> **Demo only** — Plasma testnet, mock/test USDT, no real funds.

## One-time setup (~10 min)

1. **Install Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash && foundryup
   ```
2. **Clone + configure**
   ```bash
   git clone https://github.com/sohopay/sohopay-protocol-plasma && cd sohopay-protocol-plasma
   cp .env.example .env
   ```
3. **Fill `.env`** with three testnet private keys (`DEPLOYER_PRIVATE_KEY`,
   `AGENT_PRIVATE_KEY`, `TRUSTED_SIGNER_PRIVATE_KEY`). Leave `USDC_ADDR` blank to
   use a mock USDT. Any throwaway keys work — these never touch real funds.
4. **Fund the deployer with testnet XPL** (gas) from a Plasma faucet:
   gas.zip · Chainlink · QuickNode (see [DEPLOY-PLASMA.md](DEPLOY-PLASMA.md)).

## Run the demo

```bash
./scripts/tether-demo/run-plasma-demo.sh
```

You should see Acts 1–5 print, ending with:

```
DEMO COMPLETE
```

## What just happened

| Act | What it shows |
|-----|---------------|
| 1 Setup | Deploys the audited stack; registers a Tier-2 agent + Active merchant; funds the vault |
| 2 Lend | A lender deposits USDT and receives `svUSDT` vault shares |
| 3 Settle | A signed payment settles and the merchant is paid USDT (closed-loop) |
| 4 Repay | The agent repays its credit; an overpayment is rejected |
| 5 Safety | Even with settlement paused, a lender can emergency-exit the vault |

## Share the result

```bash
./scripts/tether-demo/extract-link-pack.sh   # writes docs/tether-demo/LINK-PACK.md
```

Open the links in [LINK-PACK.md](LINK-PACK.md) on
[testnet.plasmascan.to](https://testnet.plasmascan.to) to show the live contracts and
transactions. For the talk track, see [MEETING-GUIDE.md](MEETING-GUIDE.md).
