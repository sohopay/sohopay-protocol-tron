# SOHOPay v1 — Tron USDT Demo

Tron Nile testnet deployment and walkthrough for the SOHOPay USDT demo (TRC20 + TIP-712).

This repository is the **Tron sibling** of [sohopay-protocol](https://github.com/sohopay/sohopay-protocol). Protocol logic is vendored from the EVM repo at the commit recorded in [`SYNCED_FROM`](SYNCED_FROM). EVM invariant and unit test proof remains in the sibling repo (`docs/tether-demo/artifacts/usdt-demo-green.txt`).

> **Demo only** — not audited production USDT or Tron support. Production USDC on Base is unchanged. Full gates (dual audit, FV of section 8 invariants, Gate-0 legal) still apply before real funds.

## Target network

| Item | Value |
|------|-------|
| Network | [Nile testnet](https://nile.tronscan.org) |
| JSON-RPC | `https://nile.trongrid.io/jsonrpc` |
| Chain ID | `3448148188` |
| Nile USDT (TRC20) | `TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf` |

## Status

Scaffold only. Track progress in [GitHub Issues](https://github.com/sohopay/sohopay-protocol-tron/issues).

## Quick start (when implemented)

```bash
cp .env.example .env
# fund Nile wallet (TRX + USDT via https://nileex.io/join/getJoinPage)
./scripts/sync-from-evm.sh ../sohopay-protocol
./scripts/tether-demo/run-tron-demo.sh
```

## Docs

- [`docs/tether-demo/README.md`](docs/tether-demo/README.md) — demo index (in progress)
- EVM demo reference: [sohopay-protocol/docs/tether-demo](https://github.com/sohopay/sohopay-protocol/tree/develop/docs/tether-demo)
- Spec: [sohopay-v1-interface-spec-eip712.md](https://github.com/sohopay/sohopay-protocol/blob/develop/docs/sohopay-v1-interface-spec-eip712.md)

## Repository layout

```
contracts/              # vendored from sohopay-protocol/src/ + TIP-712 override
script/                 # Forge demo scripts (Track A)
migrations/             # TronBox deploy (Track B fallback)
scripts/
  sync-from-evm.sh      # copy pinned src/ from sibling repo
  tether-demo/          # one-command 5-act demo
docs/tether-demo/       # CEO runbook, link pack, deploy guide
```
