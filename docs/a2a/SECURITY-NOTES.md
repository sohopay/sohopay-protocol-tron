# A2A Security Notes

**This experimental A2A extension is NOT automatically covered by the prior audit.**
The merchant `settleWithAttestation` path was not rewritten and may still match
previously audited behavior. A2A requires a separate review before production.

## Threats covered by tests (`sohopay-protocol/test/unit/A2A.t.sol`)

| Threat | Test |
|--------|------|
| Replay | `test_A2A_Replay_Reverts` |
| Signature substitution | `test_A2A_IntentSignerMismatch_Reverts`, invalid/untrusted att |
| Wrong payee | `test_A2A_PayeeTampering_Reverts`, attestation reuse |
| Wrong amount | `test_A2A_AmountTampering_Reverts` |
| Wrong asset | `test_A2A_AssetTampering_Reverts` |
| Wrong chain | `test_A2A_WrongDomainChainId_Reverts` |
| Wrong contract | `test_A2A_WrongVerifyingContract_Reverts` |
| Expired payment / attestation | `test_A2A_ExpiredIntent_Reverts`, `ExpiredAttestation` |
| Inactive payer / payee | `test_A2A_InactivePayer_Reverts`, `InactivePayee`, `RevokedPayee` |
| Self payment | `test_A2A_SelfPayment_Reverts` |
| Unset receive wallet | `test_A2A_UnsetReceiveAddress_Reverts` |
| Cap bypass | per-tx, daily 20+20+20, global daily, global outstanding |
| Unauthorized executor | `test_A2A_NonExecutor_Reverts` |
| Paused settlement | `test_A2A_PausedSettlement_Reverts` |
| Reentrancy | existing merchant CEI + same effects-before-transfers order |
| ERC20 transfer failure | SafeERC20; insufficient hot-float revert |
| Storage collision | `_agentReceive` appended; slots 0–17 unchanged; `__gap` 40→39 |
| Merchant disguise | `test_A2A_PhilIsNotAMerchant`, `DoesNotCallMerchantPayout` |

## Explicit non-goals

- Paying `agent.signer`
- Permissionless (non-executor) A2A
- Payee inbound daily caps
- Bilateral payee signature (v1.1)
- Production KYB exception for agents receiving commercial value

## NL / MCP

`pay_agent` only builds a structured request and invokes the executor. It must
not claim success without `A2A PAYMENT COMPLETE` / on-chain confirmation.
It must not hold protocol keys or bypass caps.
