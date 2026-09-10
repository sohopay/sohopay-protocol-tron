# A2A Architecture (experimental)

This branch adds a **parallel** Agent-to-Agent settlement path. The audited merchant
loop is unchanged.

```
Bob
 |
 | "Pay Phil's agent $20"
 v
Claude / CLI  (parse only — not a security boundary)
 |
 v
SOHOPay A2A Tool  (scripts/a2a/pay-agent.mjs or MCP pay_agent)
 |
 v
Recipient Resolver  (@handle directory → agentId / merchantId)
 |
 v
PHIL_AGENT_ID = keccak256("PHIL_AGENT")
 |
 v
IdentityRegistry
 |
 | Active?
 v
AgentPaymentIntent  +  CreditAttestation
 |
 v
Payer EIP-712 signature  +  trusted attestation signature
 |
 v
CapManager._checkPayerCaps / _checkGlobalOutstanding
 |
 v
settleAgentToAgent
 |
 | 20 USDC from settlement hot float
 v
agentReceive(PHIL_AGENT_ID)
 |
 v
Phil Agent receive wallet
```

Credit model: vault/hot-float liquidity pays Phil; Bob's `outstandingDebt` increases by
`amount + fee`. This is **not** Bob's wallet sending USDC directly.

## True A2A vs merchant disguise

| Check | A2A path |
|-------|----------|
| Phil in IdentityRegistry | required, Active |
| Phil in MerchantRegistry | **forbidden / unused** |
| Payout | `_agentReceive[payee]`, never `merchant.payout` or `agent.signer` |
| Event | `AgentToAgentSettled` (not `SettlementExecuted`) |

## INV-A2A

`settleAgentToAgent` pays only `_agentReceive[payeeAgentId]` of an Active registered
agent. It never pays an arbitrary address. The merchant path remains closed-loop
(`settleWithAttestation`).

## Audit

This experimental A2A extension is **NOT automatically covered by the prior audit.**
