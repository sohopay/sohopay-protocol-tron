# Meeting Guide — 5-Act Narrative + Q&A

A talk track for presenting the SOHOPay USDT demo on Plasma. Each act maps to one on-chain
transaction you can open live on [testnet.plasmascan.to](https://testnet.plasmascan.to).

## Setup line
> "This is the exact, audited SOHOPay settlement protocol — the same contracts we run for
> USDC on Base — deployed unchanged on Plasma, an EVM-equivalent stablecoin chain. Nothing
> in the protocol was rewritten; Plasma speaks the same EVM and EIP-712 our signatures already use."

## The five acts

**Act 1 — Setup.** We deploy the stack and onboard a Tier-2 agent (operator-bound, with an
owner→business→agent identity chain) and an Active merchant. The vault is funded with lender
USDT. *Point:* identity and caps are enforced on-chain before a cent moves.

**Act 2 — Lend.** A lender deposits USDT into the ERC-4626 vault and receives `svUSDT`
shares. *Point:* this is the liquidity that backs agent settlements.

**Act 3 — Settle.** The agent signs a `PaymentIntent`; a trusted signer co-signs a
`CreditAttestation` (both EIP-712). The settlement contract verifies both signatures, checks
caps and closed-loop merchant status, and pays the merchant USDT. *Point:* the merchant is
paid instantly; the agent's credit is drawn — all gated by signatures and caps.

**Act 4 — Repay.** The agent repays its outstanding credit. A deliberate **overpayment is
rejected** by the contract. *Point:* repayment accounting is exact and tamper-proof.

**Act 5 — Safety.** We pause settlement (guardian action), then a lender still performs an
**emergency redeem** from the vault. *Point:* lender funds are never trapped — emergency exit
works even when settlement is halted (design decision D15).

## Closing line
> "Every guarantee you just saw — signature verification, caps, closed-loop, emergency exit —
> is the same audited code path as production. Plasma gave us a stablecoin-native EVM chain
> with zero protocol changes."

## Anticipated Q&A

**Q: Did you fork or modify the contracts for Plasma?**
No. The `src/` is vendored byte-for-byte from `sohopay-protocol` at the commit pinned in
`SYNCED_FROM`. Plasma is EVM-equivalent, so no TIP-712/TVM adaptations were needed.

**Q: Is this production USDT support?**
No — demo only, testnet, with a mock/test USDT. Production USDC on Base is unchanged. Full
gates (dual audit, formal verification of the §8 invariants, Gate-0 legal) still apply.

**Q: What about gas — do users need XPL?**
The demo uses XPL gas. Plasma also has a paymaster that can sponsor USDT transfers (gasless
stablecoin sends); that's a planned follow-up, not part of this walkthrough.

**Q: Where's the test/invariant proof?**
In the EVM source repo (`sohopay-protocol`), which remains the source of truth for bytecode
logic and invariant proofs. This repo only re-deploys and demonstrates.
