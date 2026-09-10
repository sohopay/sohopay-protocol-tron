# A2A Implementation Notes

Canonical source: `sohopay-protocol` branch `feature/base-sepolia-a2a-usdc-demo`
commit `214dd0a77c813acb89a03d159bcc61f8f4f6a718`. This repo vendors `src/` via
`scripts/sync-from-evm.sh` (`SYNCED_FROM`).

## Additive surface (do not treat as a merchant rewrite)

| File | Change |
|------|--------|
| `Types.sol` | Append-only `AgentPaymentIntent` |
| `SohoEIP712.sol` | `AGENT_PAYMENT_INTENT_TYPEHASH` + `hashAgentIntent` |
| `RegistryErrors.sol` | `PayeeAgentNotActive`, `PayeeReceiveUnset`, `SelfPayment` |
| `CapManager.sol` | `_checkPayerCaps` / `_accruePayerCaps` (no merchant window) |
| `ISohoEvents.sol` | `AgentToAgentSettled`, `AgentReceiveSet` |
| `ISohoSettlement.sol` | `settleAgentToAgent`, `setAgentReceive`, `agentReceive`, A2A digests |
| `SohoSettlement.sol` | A2A settle + `_agentReceive` mapping |

## Frozen (untouched)

`PaymentIntent`, `CreditAttestation`, `PAYMENT_INTENT_TYPEHASH`,
`CREDIT_ATTESTATION_TYPEHASH`, `settleWithAttestation` body/order,
`Types.Agent` / `Types.Merchant` field order, `MerchantRegistry`.

## CreditAttestation reuse

`paymentId = hashAgentIntent(intent)`. Attestation binds `paymentId`, payer
`agentId`, asset, amount, fee. Changing the payee after signing changes the
hash → `AttestationIntentMismatch`.

## Receive address

`mapping(bytes32 => address) _agentReceive` at SohoSettlement slot **18**.
`__gap` reduced **40 → 39** (starts at slot 19). Slots 0–17 unchanged.

`setAgentReceive` is `TREASURY_ROLE`. Zero address and unknown agents revert.
Unset receive reverts at settle (`PayeeReceiveUnset`). Never defaults to signer.

## Payee validation

- exists and Active; Revoked → `AgentRevoked`
- `payer != payee` → `SelfPayment`
- tier-2: Active business + owner (identity chain). Mandate is **payer-only**.

## Caps

A2A: payer per-tx, payer daily, global daily, global outstanding.
Merchant daily is not read or accrued.

## Demo

Isolated deploy (`script/DemoBaseA2A.s.sol`): deployer is treasury/admin so one
broadcast can register Bob + Phil and settle 20 USDC. Fee is **0** (current
intent-specified fee; no invented 5% fee).
