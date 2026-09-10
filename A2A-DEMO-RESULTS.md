# A2A Demo Results

## Branch

```text
feature/base-sepolia-a2a-usdc-demo
```

Canonical protocol: `sohopay-protocol` @ `214dd0a77c813acb89a03d159bcc61f8f4f6a718`
(same branch name). This repo `SYNCED_FROM` matches that commit.

MCP: same experimental branch; `pay_agent` is unpublished and executor-backed.
Production MCP catalog is unchanged.

## Architecture

Additive parallel path. Bob signs `AgentPaymentIntent`; a reused `CreditAttestation`
binds `paymentId = hashAgentIntent(...)`. `settleAgentToAgent` pays
`_agentReceive[PHIL_AGENT_ID]` from settlement hot float and increases Bob's
`outstandingDebt`. Merchant `settleWithAttestation` is untouched.

## True A2A

```text
YES
```

## Phil registered as Agent

```text
YES
```

## Phil required as Merchant

```text
NO
```

## Local tests

```text
PASS
```

Protocol: 247/247. Local isolated demo: Phil balance after = `20000000`;
Bob debt = `20000000`; `A2A PAYMENT COMPLETE`; 30 USDC per-tx block reverted.

## Existing Merchant Regression

```text
PASS
```

`SohoSettlementTest` + settlement invariants green. Plasma 5-act demo printed
`DEMO COMPLETE` (merchant received 50 USDT).

## Base Sepolia Deployment

```text
NOT RUN / BLOCKED
```

No `BASE_SEPOLIA_RPC_URL`, deployer key, gas ETH, or test USDC were configured.
Stopped at **READY FOR BASE SEPOLIA EXECUTION**. Isolated local deploy used
`MockUSDC` at chain id 84532.

## 20 USDC Testnet Transfer

```text
NOT RUN / BLOCKED
```

## Natural Language Demo

```text
PASS
```

`node scripts/a2a/pay-agent.mjs "Pay Phil's agent $20"` and `pay @phil 20`
resolve to handle `@phil` (registered agent, not merchant). `pay @acme 6`
resolves to the demo merchant. Parsing does not authorize settlement.

Onboarding (`sohopay`): name + demo phone OTP → unique `@handle` + $20 credit.

## MCP Demo

```text
NOT IMPLEMENTED
```

Thin local stdio server: `scripts/a2a/mcp-server.mjs`.
`sohopay-mcp-server` unpublished `PayAgent.ts` on the experimental branch only
(not in `tools/list`). Production MCP was not republished.

## Transaction Hash

```text
N/A
```

## BaseScan

```text
N/A
```

## Security Test Results

| Test | Result |
|------|--------|
| `test_AgentToAgent_20USDC_Succeeds` | PASS |
| `test_A2A_PhilIsNotAMerchant` | PASS |
| `test_A2A_DoesNotCallMerchantPayout` | PASS |
| `test_A2A_SelfPayment_Reverts` | PASS |
| `test_A2A_InactivePayee_Reverts` | PASS |
| `test_A2A_RevokedPayee_Reverts` | PASS |
| `test_A2A_UnsetReceiveAddress_Reverts` | PASS |
| `test_A2A_Replay_Reverts` | PASS |
| `test_A2A_PayeeTampering_Reverts` | PASS |
| `test_A2A_AttestationCannotReuseAgainstDifferentPayee` | PASS |
| `test_A2A_AmountTampering_Reverts` | PASS |
| `test_A2A_AssetTampering_Reverts` | PASS |
| `test_A2A_WrongDomainChainId_Reverts` | PASS |
| `test_A2A_WrongVerifyingContract_Reverts` | PASS |
| `test_A2A_AbovePerTransactionCap_Reverts` | PASS |
| `test_A2A_DailyCap_TwoTimes20Then20Reverts` | PASS |
| `test_A2A_GlobalDailyCap_Reverts` | PASS |
| `test_A2A_GlobalOutstandingCap_Reverts` | PASS |
| `test_A2A_DebtAccountingAndRepay` | PASS |
| `test_A2A_PausedSettlement_Reverts` | PASS |
| `test_A2A_NonExecutor_Reverts` | PASS |
| `test_MerchantPath_StillSettlesAfterA2A` | PASS |
| `test_MerchantTypehash_Unchanged` | PASS |

## Contract Changes

Protocol (then synced into this repo `src/`):

- `src/libraries/Types.sol`
- `src/libraries/SohoEIP712.sol`
- `src/base/RegistryErrors.sol`
- `src/base/CapManager.sol`
- `src/interfaces/ISohoEvents.sol`
- `src/interfaces/ISohoSettlement.sol`
- `src/SohoSettlement.sol`

Demo-only (this repo): `script/DemoBaseA2A.s.sol`, `scripts/a2a/*`, `docs/a2a/*`.

## Storage layout

| Slot | Name |
|------|------|
| 0–17 | unchanged (`treasuryController` = 17) |
| 18 | `_agentReceive` (new) |
| 19 | `__gap` `uint256[39]` (was 40 at slot 18) |

## Audit Impact

**This experimental A2A extension is NOT automatically covered by the prior audit.**
The merchant path was not rewritten. New A2A code needs a separate review before
production. Do not describe the modified settlement contract as fully audited.

## Remaining Production Gaps

- Live Base Sepolia 20 USDC transfer (RPC, gas, test USDC, keys)
- Bilateral payee signature
- Gate-0 / KYB for agents receiving value without merchant KYB
- Production MCP catalog + backend executor
- Dedicated A2A audit / FV
