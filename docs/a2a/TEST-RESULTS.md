# A2A Test Results

Recorded from `sohopay-protocol` @ `214dd0a` on branch
`feature/base-sepolia-a2a-usdc-demo`.

## Protocol suite

```text
Ran 13 test suites: 247 tests passed, 0 failed, 0 skipped
```

Includes existing merchant unit + invariant suites (`SettlementInvariants`,
`VaultInvariants`, `GovernanceInvariants`) and new `A2ATest` (39 tests) plus
payer-only `CapManager` cases.

## Storage layout (SohoSettlement)

| Slot | Name | Notes |
|------|------|-------|
| 0–17 | existing | unchanged (`treasuryController` still slot 17) |
| 18 | `_agentReceive` | **new** mapping |
| 19 | `__gap` | `uint256[39]` (was `[40]` at slot 18) |

`VerifyDeployment` still reads global-cap slots 0–2; those did not move.
