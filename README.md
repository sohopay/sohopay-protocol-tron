# SOHOPay v1 — Plasma USDT Demo

Plasma testnet deployment and walkthrough for the SOHOPay USDT demo (ERC-20 + EIP-712).

This repository is the **Plasma sibling** of [sohopay-protocol](https://github.com/sohopay/sohopay-protocol). Protocol logic is vendored from the EVM repo at the commit recorded in [`SYNCED_FROM`](SYNCED_FROM). Because Plasma is **EVM-equivalent**, the audited contracts are deployed **unchanged** — no TIP-712 override, no TronWeb/TronBox, no address conversion. EVM invariant and unit test proof remains in the sibling repo.

> **Demo only** — not audited production USDT or Plasma support. Production USDC on Base is unchanged. Full gates (dual audit, FV of section 8 invariants, Gate-0 legal) still apply before real funds.

## Target network

| Item | Value |
|------|-------|
| Network | [Plasma testnet](https://testnet.plasmascan.to) |
| JSON-RPC | `https://testnet-rpc.plasma.to` |
| Chain ID | `9746` |
| Native token | `XPL` (gas faucet: gas.zip / Chainlink / QuickNode) |
| Settlement asset | mock 6-decimal ERC-20 (default) or `USDC_ADDR` override |

> Mainnet USDT0 is `0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb` (6-decimal). There is no
> public USDT0 on testnet, so the demo deploys a mock 6-decimal ERC-20 unless `USDC_ADDR` is set.

## Status

Implemented. The 5-act demo compiles and runs green (`DEMO COMPLETE`) at chain 9746.
See [`docs/PLASMA-IMPLEMENTATION-PLAN.md`](docs/PLASMA-IMPLEMENTATION-PLAN.md) and track
progress in [GitHub Issues](https://github.com/sohopay/sohopay-protocol-plasma/issues).

## Quick start

```bash
cp .env.usdt-demo.plasma.example .env.usdt-demo.plasma   # add 3 throwaway testnet keys
# deps are pinned in foundry.lock (audited OZ commits) — do NOT install unpinned
forge install                                            # or: git submodule update --init --recursive
# run the self-contained 5-act demo (deploys a mock USDT; prints DEMO COMPLETE)
ENV_FILE=.env.usdt-demo.plasma ./scripts/tether-demo/run-plasma-demo.sh
```

For a persistent on-chain testnet deploy (real Plasmascan links), fund the deployer with
XPL and run `ENV_FILE=.env.usdt-demo.plasma ./scripts/tether-demo/deploy-plasma-testnet.sh`.

## Docs

- [`docs/PLASMA-IMPLEMENTATION-PLAN.md`](docs/PLASMA-IMPLEMENTATION-PLAN.md) — full implementation plan
- [`docs/tether-demo/README.md`](docs/tether-demo/README.md) — demo index (in progress)
- EVM demo reference: [sohopay-protocol/docs/tether-demo](https://github.com/sohopay/sohopay-protocol/tree/develop/docs/tether-demo)
- Spec: [sohopay-v1-interface-spec-eip712.md](https://github.com/sohopay/sohopay-protocol/blob/develop/docs/sohopay-v1-interface-spec-eip712.md)

## Repository layout

```
src/                    # vendored from sohopay-protocol/src/ (Plasma deploys it unchanged)
script/                 # Forge deploy + 5-act demo scripts
test/mocks/             # mock ERC-20 for the self-contained testnet demo
scripts/
  sync-from-evm.sh      # copy pinned src/ from sibling repo + record SHA
  tether-demo/          # one-command 5-act demo + link-pack extractor
docs/tether-demo/       # CEO runbook, deploy guide, meeting guide, link pack
foundry.toml            # Plasma testnet RPC + Plasmascan verify config
```
