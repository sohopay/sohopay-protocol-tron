# Deploy Guide — Plasma Testnet

## Network

| Item | Value |
|------|-------|
| Network | Plasma testnet |
| Chain ID | `9746` |
| RPC | `https://testnet-rpc.plasma.to` |
| Explorer | `https://testnet.plasmascan.to` |
| Native gas token | `XPL` |

Configured in [`foundry.toml`](../../foundry.toml) as the `plasma_testnet` endpoint
(reads `PLASMA_RPC` from `.env`).

## Funding

### Gas (XPL)
Plasma testnet gas is paid in **XPL**. Get testnet XPL from a faucet:
- gas.zip faucet for Plasma
- Chainlink faucets (Plasma testnet)
- QuickNode Plasma testnet faucet

> Plasma also offers a protocol **paymaster that can sponsor USDT transfers** (gasless
> stablecoin sends). The demo uses ordinary XPL gas for simplicity; sponsored-gas
> integration is a follow-up, not required for the 5-act walkthrough.

### Settlement asset (USDT)
There is **no public USDT0 on Plasma testnet**. Options:
1. **Default (recommended for the demo):** leave `USDC_ADDR` blank — the demo deploys a
   mock 6-decimal `MockUSDT` and mints balances automatically.
2. **Real token:** set `USDC_ADDR` to a 6-decimal ERC-20 the deployer already holds.

> Mainnet USDT0 is `0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb` (6-decimal, verified
> on-chain). Mainnet (chain 9745) deployment is out of scope for this demo.

## Two deploy paths

### A. One-command demo (self-contained)
```bash
./scripts/tether-demo/run-plasma-demo.sh
```
Deploys with a **zero timelock** and the deployer as admin so the whole 5-act story runs
in one transaction stream. Demo only.

### B. Production-style deploy (timelocked)
```bash
./scripts/tether-demo/deploy-plasma.sh
```
Uses the vendored `script/Deploy.s.sol`: CREATE2 deterministic addresses, 48h timelock,
deployer renounces all roles to the Treasury Safe. Set role addresses + `USDC_ADDR` in
`.env` first. For a live timelock, use `DEPLOY_PHASE=schedule` then `DEPLOY_PHASE=execute`
after `MIN_DELAY` (see the Deploy.s.sol header).

## EVM-version note
`foundry.toml` targets `evm_version = "cancun"` to keep the bytecode byte-identical to the
audited Base build. If a Plasma deploy rejects a cancun opcode, downshift to `shanghai` and
rebuild (see `docs/PLASMA-IMPLEMENTATION-PLAN.md` §6).

## Verify on Plasmascan
Pass `--verify --verifier blockscout --verifier-url https://testnet.plasmascan.to/api`
(the wrappers do this automatically when `PLASMASCAN_API_KEY` is set).
