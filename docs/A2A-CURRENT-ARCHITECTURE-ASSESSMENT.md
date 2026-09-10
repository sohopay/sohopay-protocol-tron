# A2A Current Architecture Assessment

**Repo:** `sohopay-protocol-tron` (Plasma sibling; branch `sohopay-protocol-plasma-implementation-01`)  
**Scope:** read-only analysis of vendored v1 settlement. No source changes in this pass.  
**Question:** can this stack do **true Agent-to-Agent settlement** today?  
**Verdict:** **NO**

---

## 0. What “true A2A” means here

True Agent-to-Agent settlement means all of the following:

1. **Payer is an Agent** — registered identity chain, Active, signer-bound, caps + `outstandingDebt`.
2. **Payee is an Agent** — registered in `IdentityRegistry`, not a `Merchant`.
3. **On-chain payee check is agent-native** — Active (and tier-2 owner/business/mandate if launch path), not `MerchantNotActive`.
4. **Signed intent names a payee agent** — not `merchantId`.
5. **Payout does not require `MerchantRegistry`** — funds go to the payee agent’s receive address.
6. **Payee agent status gates receipt** — revoke/pause of the *agent* blocks receive (not a parallel merchant record).

Optional but recommended for *bilateral* A2A: the payee agent’s signer accepts the payment (second EIP-712 sig). Without that, the flow is still “agent-credit push to another agent,” not a two-sided agent handshake.

**Not true A2A:** register the receiving agent’s wallet as a merchant and settle the existing Agent→Merchant path.

---

## 1. Verdict

| Question | Answer |
|----------|--------|
| True Agent-to-Agent settlement today? | **NO** |
| Agent→Merchant credit settlement today? | **YES** (this is the entire v1 path) |
| Operational workaround (agent dual-registered as merchant)? | **PARTIAL** (off-protocol; see §3.3) |

v1 is frozen as **closed-loop Agent → registered Merchant**. There is no payee-agent type, no A2A settle function, no agent receive address, and no payee-agent signature. Caps, events, and EIP-712 typehashes are merchant-shaped.

This repo’s `src/` is vendored unchanged from `sohopay-protocol` (`SYNCED_FROM` = `f44ffc07691aa787c7efbfe854b84e9201bb4ad7`). A2A cannot be “Plasma-only” without breaking that invariant.

---

## 2. Current settlement architecture (what exists)

```
Owner (KYC) → Business (KYB) → Agent (KYA, payer)
                                      │
                                      │ PaymentIntent + CreditAttestation
                                      │ (EIP-712, EXECUTOR_ROLE submits)
                                      ▼
                              SohoSettlement
                                      │
                    step 9 + 17: CLOSED-LOOP (INV-6L)
                                      │
                                      ▼
                              Merchant.payout  +  feeRecipient
                                      │
                         Agent.outstandingDebt += amount+fee
                                      │
                                      ▼
                              repay() → Vault.receiveRepayment
```

### 2.1 Roles of the two parties

| Party | Type | What the chain knows | What settlement does |
|-------|------|----------------------|----------------------|
| Payer | `Types.Agent` | signer, tier, mandate, per-tx/daily caps, `outstandingDebt` | Verify Active + sig; draw credit; accrue caps |
| Payee | `Types.Merchant` | `payout`, daily cap, Active/Paused only | Must be Active; transfer to `payout` |

Agents cannot receive. Merchants cannot borrow. The maps `_agents` and `_merchants` are independent; sharing a `bytes32` id does not unify them.

### 2.2 Normative 19-step order (`settleWithAttestation`)

Source: `src/SohoSettlement.sol` `settleWithAttestation` (comment: “DO NOT REORDER”).

| Step | Behavior | A2A implication |
|------|----------|-----------------|
| 1 | `whenNotPaused` + `EXECUTOR_ROLE` | A2A would still be executor-submitted unless a new entry is added |
| 2–7 | `paymentId = hashIntent`; replay/revoke/expiry; att binds intent | Hash includes `merchantId` |
| 8 | Payer agent Active; tier-2 business/owner/mandate | Payer-agent path is reusable |
| **9** | **Merchant Active (`MerchantNotActive`)** | **Hard payee-type lock** |
| 10–12 | Asset + agent ECDSA + trusted attestation | Payer-only; no payee sig |
| 13–16 | Caps include **merchant daily**; debt on **payer agent** | Cap API requires `Types.Merchant storage` |
| **17** | **`safeTransfer(merchant.payout, amount)`** | **No agent receive address** |
| 18–19 | Fee + `SettlementExecuted(..., merchantId)` | Event surface is merchant-indexed |

### 2.3 Frozen signed types

`Types.sol` is marked **FROZEN**. Changing existing structs invalidates in-flight messages and storage assumptions.

```
PaymentIntent  { agentId, merchantId, asset, amount, feeAmount, orderRef, nonce, deadline }
CreditAttestation { paymentId, agentId, asset, amount, feeAmount, deadline }
```

Typehashes in `SohoEIP712.sol` are equally frozen:

- `PaymentIntent(bytes32 agentId,bytes32 merchantId,...)`
- `CreditAttestation(bytes32 paymentId,bytes32 agentId,...)`

`CreditAttestation` names only the **payer** `agentId`. Payee identity is only inside `paymentId` via `merchantId`.

### 2.4 What agents lack vs merchants

`Types.Agent` has: `businessId`, `signer`, tier/caps, `outstandingDebt`, mandate, status, outbound daily window.  
**No payout / receive address.**

`Types.Merchant` has: `payout`, inbound daily window, Active/Paused.  
**No signer, mandate, debt, identity chain.**

Paying `agent.signer` would be a dangerous stand-in: `signer` is the Turnkey MPC EOA used for EIP-712, 1:1 with the agent (`_signerToAgent`), not a treasury receive wallet.

---

## 3. Exact files / functions — enable vs prevent

### 3.1 Prevent true A2A (blockers)

| File | Symbol | Why it blocks |
|------|--------|----------------|
| `src/SohoSettlement.sol` | `settleWithAttestation` steps **9, 13, 16, 17, 19** | Payee **must** be Active merchant; payout **must** be `merchant.payout`; event is `merchantId` |
| `src/SohoSettlement.sol` | `registerMerchant` / `setMerchantPayout` / `setMerchantStatus` | Only merchant onboarding for payees |
| `src/libraries/Types.sol` | `PaymentIntent.merchantId` | Signed payee is a merchant id |
| `src/libraries/Types.sol` | `Types.Agent` | No receive address; receive is not an agent concern |
| `src/libraries/Types.sol` | `MerchantNotActive` | Closed-loop error is the only payee-status revert |
| `src/libraries/SohoEIP712.sol` | `PAYMENT_INTENT_TYPEHASH` / `hashIntent` | Frozen encoding includes `merchantId` |
| `src/base/MerchantRegistry.sol` | `_registerMerchant`, `_setMerchantPayout`, `getMerchant` | “Payout side of closed-loop” (header: D-CLOSEDLOOP, spec §3.1 steps 9 & 17) |
| `src/base/CapManager.sol` | `_checkCaps` / `_accrueCaps` | Signature is `(Agent, Merchant, amount)` — merchant daily is mandatory |
| `src/interfaces/ISohoEvents.sol` | `SettlementExecuted(..., merchantId, ...)` | Indexed payee is merchant |
| `src/interfaces/ISohoSettlement.sol` | surface | No A2A function; merchants section labeled D-CLOSEDLOOP |
| `script/DemoPlasma.s.sol` | `_act3_settle` | Builds `PaymentIntent` with `MERCHANT_ID`; asserts merchant balance |
| Policy comments | D-CLOSEDLOOP / INV-6L | Product invariant: registered merchant only |

### 3.2 Enable a future additive A2A (reusable, do not mutate)

| File | Symbol | Why it helps |
|------|--------|----------------|
| `src/SohoSettlement.sol` | `settleWithAttestation` steps **1–8, 10–12, 14–16 (payer debt)** | Pause, replay, expiry, payer identity, asset, dual sig, hot-float, CEI, payer debt |
| `src/SohoSettlement.sol` | `repay` | Payer debt unwind is party-agnostic (keyed by `agentId`) |
| `src/SohoSettlement.sol` | `usedPayments` / `revokedPayments` | Shared replay table if A2A `paymentId` uses a **new** typehash |
| `src/base/IdentityRegistry.sol` | `_registerAgent`, `_agents`, `getAgent`, signer 1:1 | Second agent can already be registered as a **payer-shaped** record |
| `src/base/IdentityRegistry.sol` | step-8 style Active + tier-2 chain | Copy for **payee** agent checks |
| `src/base/CapManager.sol` | `_checkGlobalOutstanding` / `_accrueOutstanding` / `_releaseOutstanding` | Global credit cap is payee-type-agnostic |
| `src/libraries/SohoEIP712.sol` | `hashAttestation` + `CREDIT_ATTESTATION_TYPEHASH` | Reusable **if** `paymentId = hash(A2A intent)` (payee bound through the hash) |
| `src/SohoVault.sol` | `receiveRepayment` / `recognizeLoss` | No merchant assumption; stays payer-agent keyed |
| `src/SohoTreasuryController.sol` | existing roles / timelock | No new controller needed for a TREASURY/CREDIT_ADMIN-gated receive-address setter |

### 3.3 PARTIAL workaround (not true A2A)

Operator can:

1. `registerAgent(payeeAgentId, ...)` so B is an agent (unused at settle).
2. `registerMerchant(someMerchantId, B_wallet, dailyCap)`.
3. A signs `PaymentIntent{ agentId: A, merchantId: someMerchantId }`.
4. `settleWithAttestation` pays `B_wallet`.

Why this is **not** true A2A:

- Payee check is merchant Active, not agent Active.
- Revoking agent B does **not** stop receipt if the merchant stays Active.
- B does not sign; B’s mandate/tier/signer are unused.
- Caps accrue on the merchant window, not on B as agent.
- Events/indexers still see a merchant payment.
- Violates the *spirit* of D-CLOSEDLOOP (merchant KYB) while keeping the *letter* (a merchant row exists).

Do not treat dual-registration as an A2A implementation.

---

## 4. Minimum proposed implementation

**Design rule:** do **not** edit `PaymentIntent`, `CreditAttestation`, their typehashes, or the 19-step `settleWithAttestation` order. Those are frozen. Add a parallel A2A path.

### 4.1 Additive types (append only)

In `Types.sol` (new struct; do not reorder existing ones):

```text
struct AgentPaymentIntent {
    bytes32 payerAgentId;
    bytes32 payeeAgentId;
    address asset;
    uint256 amount;
    uint256 feeAmount;
    bytes32 orderRef;
    uint256 nonce;
    uint256 deadline;
}
```

New typehash + `hashAgentIntent` in `SohoEIP712.sol`.  
`paymentId = hashAgentIntent(intent)` — disjoint from current `hashIntent` (different typehash).

**Reuse** `CreditAttestation` unchanged: `att.paymentId == paymentId` binds payee through the A2A hash; `att.agentId == payerAgentId`.

New errors (prefer `RegistryErrors.sol` or additive `Types` errors): `PayeeAgentNotActive`, `SelfPayment`, `PayeeReceiveUnset` (if receive address is required).

New event (do not overload `SettlementExecuted`):

```text
AgentToAgentSettled(paymentId, payerAgentId, payeeAgentId, asset, amount, feeAmount, orderRef)
```

### 4.2 Receive address (no `Types.Agent` layout change)

Do **not** add fields to `Types.Agent` (storage layout + audit).

Add append-only mapping on settlement / identity module, consuming `SohoSettlement`’s `__gap` correctly:

```text
mapping(bytes32 => address) internal _agentReceive; // TREASURY sets; 0 = unset
```

Minimum policy: **unset receive address reverts**. Do not default to `agent.signer`.

### 4.3 New entry: `settleAgentToAgent`

Same modifiers as today: `whenNotPaused` + `EXECUTOR_ROLE`.

Suggested check order (mirror 19 steps, swap merchant for payee agent):

1. Pause + executor.
2. `paymentId = hashAgentIntent`.
3–4. Not used / not revoked.
5–6. Intent + attestation deadlines.
7. Attestation binds `paymentId`, `payerAgentId`, asset, amount, fee.
8. **Payer** agent Active + tier-2 chain + mandate (copy of current step 8).
9. **Payee** agent exists, Active, not Revoked; if tier-2, business/owner Active (mandate optional for *receive*).
10. `payerAgentId != payeeAgentId`.
11. Supported asset; hot-float ≥ amount+fee.
12. Payer intent ECDSA vs `payer.signer`.
13. Trusted attestation (existing `SignatureChecker` path).
14. Caps: **payer per-tx + payer daily + global daily + global outstanding**. **No merchant window.** Requires new CapManager helpers (see §4.4).
15. `_agentReceive[payeeAgentId] != 0`.
16. Effects: consume replay; accrue payer + global caps; `payer.outstandingDebt += amount+fee`.
17. `safeTransfer(_agentReceive[payee], amount)` + fee to `feeRecipient`.
18. `emit AgentToAgentSettled`.

**Bilateral (recommended v1.1, not required for first cut):** payee signs `AgentPaymentIntent` (or a thin `AgentAcceptance { paymentId, payeeAgentId }`). Recover `payee.signer`. This is the difference between “push to an agent address” and “two agents agreed.”

### 4.4 CapManager split (required)

Today `_checkCaps(agent, merchant, amount)` cannot run without a merchant.

Add:

- `_checkPayerCaps(Types.Agent storage payer, uint96 amount)` — per-tx, payer daily, global daily.
- `_accruePayerCaps(...)` — same windows, no merchant.

Leave `_checkCaps` / `_accrueCaps` untouched for the merchant path.

Payee inbound daily caps are **out of minimum scope** (can be a later mapping). Global outstanding still applies (same credit pot).

### 4.5 What not to touch

| Keep frozen | Reason |
|-------------|--------|
| `settleWithAttestation` body / step order | Spec §3.1 / audit surface |
| `PaymentIntent` / `CreditAttestation` / existing typehashes | In-flight messages + off-chain signers |
| `Types.Agent` / `Types.Merchant` field order | Storage layout |
| Vault credit hooks | Already agent-id keyed |
| Merchant closed-loop path | Production Agent→Merchant stays the default |

### 4.6 Policy / legal (not optional to name)

A2A is an **explicit exception to D-CLOSEDLOOP / INV-6L**. New invariant:

> **INV-A2A:** `settleAgentToAgent` pays only `_agentReceive[payeeAgentId]` of an Active registered agent. It never pays an arbitrary address. The merchant path remains closed-loop.

Gate-0 / KYB questions (agent receiving commercial value without merchant KYB) are **out of contract scope** but must be decided before mainnet enablement. Demo/testnet can ship the function behind the same executor + attestation trust model.

### 4.7 Demo (this repo)

After protocol sync: second agent (`PAYEE_AGENT_ID`), TREASURY-set receive address, one new act (or `script/DemoA2A.s.sol`) that:

- registers payer + payee agents (no merchant row for the payee),
- settles A2A,
- asserts payee receive balance == amount,
- asserts `getMerchant(payeeAgentId).status == None`,
- existing 5-act merchant demo remains green.

---

## 5. Exact repository / file change plan

### 5.1 Which repo

| Repo | Role |
|------|------|
| **`sohopay-protocol`** (EVM source of truth) | **Implement protocol A2A here first.** Invariant tests, FV notes, interface spec. |
| **`sohopay-protocol-tron` / plasma sibling (this repo)** | `./scripts/sync-from-evm.sh` to refresh `src/` + `SYNCED_FROM`. Then Plasma demo/docs only. |
| **`sohopay-protocol` docs** | `#6`-style pointer: A2A is demo/extension, not a change to production USDC-on-Base merchant loop until gates pass. |

Do **not** fork `src/` only on the Plasma branch. That breaks “vendored bytecode unchanged.”

### 5.2 File plan — protocol (`sohopay-protocol`, then sync)

| File | Change | Risk |
|------|--------|------|
| `src/libraries/Types.sol` | **Append** `AgentPaymentIntent` + additive errors. No field edits on existing structs. | Low if append-only; **High** if existing structs move |
| `src/libraries/SohoEIP712.sol` | Add `AGENT_PAYMENT_INTENT_TYPEHASH` + `hashAgentIntent`. Do not edit existing typehashes. | Low |
| `src/base/RegistryErrors.sol` | Optional: `SelfPayment`, `PayeeReceiveUnset` (keeps Types frozen) | Low |
| `src/base/IdentityRegistry.sol` | Optional view `agentReceive` if mapping lives here; otherwise leave | Low |
| `src/base/CapManager.sol` | Add `_checkPayerCaps` / `_accruePayerCaps`. Do not change merchant helpers. | Medium (cap invariants) |
| `src/interfaces/ISohoEvents.sol` | Add `AgentToAgentSettled` | Low |
| `src/interfaces/ISohoSettlement.sol` | Add `settleAgentToAgent`, `setAgentReceive`, `agentReceive`, `agentIntentDigest` | Low |
| `src/SohoSettlement.sol` | Implement settle + receive-address setter (`TREASURY_ROLE`); shrink `__gap` for new storage | Medium (upgrade layout) |
| `src/SohoVault.sol` | **No change** | — |
| `src/SohoTreasuryController.sol` | **No change** | — |
| `src/SohoFirstLossReserve.sol` | **No change** | — |
| `src/base/MerchantRegistry.sol` | **No change** | — |
| Tests (EVM repo) | New `test/A2A.t.sol`: happy path, self-pay revert, inactive payee, unset receive, replay, merchant path regression | Required |
| Spec / DECISIONS | INV-A2A, exception to D-CLOSEDLOOP, typehash freeze note | Required for audit |

### 5.3 File plan — this Plasma repo (after sync)

| File | Change |
|------|--------|
| `src/**` | **Only via `sync-from-evm.sh`** — no hand edits |
| `SYNCED_FROM` | New pinned SHA |
| `script/DemoA2A.s.sol` (new) or extra act in `DemoPlasma.s.sol` | Two-agent settle; keep merchant 5-act intact |
| `scripts/tether-demo/run-plasma-a2a-demo.sh` (new) | One-command `A2A DEMO COMPLETE` |
| `docs/tether-demo/A2A-MEETING-GUIDE.md` (new) | Talk track; disclaimer: not production A2A |
| `docs/A2A-CURRENT-ARCHITECTURE-ASSESSMENT.md` | This file (assessment only) |
| `README.md` | Link A2A demo as extension, not replacement |

### 5.4 Suggested commit cadence (when implementation is authorized)

1. `docs: A2A assessment` (this file) — **done in this pass**
2. `feat(a2a): additive types + EIP-712 hash` (EVM repo)
3. `feat(a2a): CapManager payer-only helpers`
4. `feat(a2a): settleAgentToAgent + receive address`
5. `test(a2a): unit + merchant-path regression`
6. `chore: sync src from evm @ <sha>` (this repo)
7. `feat(a2a): Plasma A2A demo script + docs`

Do not open an `A2A` git branch until implementation is requested.

### 5.5 Out of minimum scope (do not include in first cut)

- Changing `PaymentIntent.merchantId` → generic `payeeId`
- Payee inbound daily caps
- Paying `agent.signer` as default
- Permissionless (non-`EXECUTOR_ROLE`) A2A
- Agent-to-EOA or open-loop payout
- Cross-agent netting / both sides taking debt
- x402 / MCP / backend session changes (separate stack)

---

## 6. Stop condition

Analysis complete. No protocol source was modified in the analysis pass.  
**Wait for an explicit implementation instruction** before creating an A2A branch or writing Solidity.
