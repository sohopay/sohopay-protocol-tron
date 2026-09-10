# Base Sepolia A2A Demo

## Target

| Item | Value |
|------|-------|
| Network | Base Sepolia |
| Chain ID | `84532` |
| Asset | USDC (6 decimals) |
| Official USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` ([Circle](https://developers.circle.com/stablecoins/usdc-contract-addresses)) |
| Amount | 20 USDC = `20_000_000` |
| Deployment | **fresh isolated test deployment** (not the production Base merchant stack) |

Do not use Plasma chain `9746` for this demo.

## Onboarding shell (recommended)

Venmo-style agent demo: type `sohopay`, create an identity, then pay a handle.

```bash
./scripts/a2a/install-sohopay-cli.sh
sohopay
```

1. Enter **name** and **phone** (demo SMS code is printed — no real text).
2. Accept a unique `@handle` (or type another).
3. Receive a **$20 SohoPay credit line**.
4. Pay in natural language:

```text
> pay @phil 20
> Pay Phil's agent $20
> pay 6 usdc to @acme
> pay 20 to 0x178905fE008BfD6B743406fcFDA01D98F68CF790
> balance
> people
> quit
```

`@phil` is a registered **agent** (A2A). `@acme` is a registered **merchant**.
A raw `0x` address pays only if it is already a directory receive/payout.
Ambiguous first names do not settle — use the unique `@handle`.

Identity is stored at `~/.sohopay/a2a-demo-identity.json`. Reset with
`sohopay --reset` or type `logout`.

Default mode is demo (no chain write). `EXECUTE=1 sohopay` runs the isolated
20 USDC `@phil` Foundry fixture and only claims success after
`A2A PAYMENT COMPLETE`.

## Local protocol fixture

```bash
./scripts/a2a/run-base-a2a-demo.sh
```

In-memory Foundry script at chain 84532 with `MockUSDC`. Prints
`A2A PAYMENT COMPLETE` after Phil receives exactly 20 USDC.

Parse only:

```bash
node scripts/a2a/pay-agent.mjs "Pay Phil's agent $20"
```

## Base Sepolia (live)

Copy placeholders:

```bash
cp .env.a2a.base-sepolia.example .env.a2a.base-sepolia
```

Required: `BASE_SEPOLIA_RPC_URL`, throwaway private keys, official `USDC_ADDR`,
`PHIL_RECEIVE_ADDRESS`, deployer ETH for gas, and test USDC for hot-float.

```bash
NETWORK=base-sepolia ENV_FILE=.env.a2a.base-sepolia ./scripts/a2a/run-base-a2a-demo.sh
```

If keys / gas / test USDC are missing the runner stops at
`READY FOR BASE SEPOLIA EXECUTION` and does not fake a transaction.

## Agents

| Agent | Registry | Merchant | Receive |
|-------|----------|----------|---------|
| Bob | IdentityRegistry Active | n/a (payer) | configured, unused for this pay |
| Phil | IdentityRegistry Active | **None** | `PHIL_RECEIVE_ADDRESS` |

Onboarded-user caps for the demo: per-tx **20 USDC**, credit line **20 USDC**.
`pay @phil 20` passes once; a second 20 or `25` is blocked. The protocol
fixture still uses Bob's 25 / 50 caps on-chain.
