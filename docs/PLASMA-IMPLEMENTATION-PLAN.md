# SOHOPay → Plasma: Full Implementation Plan

Port the SOHOPay 5-act USDT demo from the EVM source of truth
([sohopay-protocol](https://github.com/sohopay/sohopay-protocol)) to the
**Plasma testnet**. Plasma is an **EVM-equivalent L1**, so the Tron-specific
work (TIP-712 override, TronWeb, TronBox, address conversion) is **not needed**.

> **Demo only** — not audited production USDT/Plasma support. Production USDC on
> Base is unchanged. Full gates (dual audit, FV of section 8 invariants, Gate-0
> legal) still apply before real funds.

---

## 1. Verified facts (spike results, 2026-06-24)

| Item | Value | How verified |
|------|-------|--------------|
| Testnet chain id | `9746` (`0x2612`) | `eth_chainId` on `https://testnet-rpc.plasma.to` |
| Testnet RPC | `https://testnet-rpc.plasma.to` | reachable |
| Testnet explorer | `https://testnet.plasmascan.to` | — |
| Mainnet chain id | `9745` | docs |
| Mainnet RPC / explorer | `https://rpc.plasma.to` / `https://plasmascan.to` | — |
| Native token | `XPL` | docs |
| **Mainnet** USDT0 | `0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb`, **6 decimals** | `eth_getCode` + `decimals()` on mainnet RPC |
| **Testnet** USDT0 | **unknown** — `0xB8CE…625ebb` has **no code on testnet** | `eth_getCode` returns `0x` |
| Gas faucet | gas.zip / Chainlink / QuickNode Plasma faucets | docs |

**Consequences**
- USDT is **6-decimal**, matching the EVM deploy config assumption
  (`$100 == 100e6`) — amount math is unchanged.
- The testnet demo asset will be a **deployed mock 6-decimal ERC-20**
  (`USDT_ADDR` env override lets the real testnet/mainnet token be swapped in).
- `forge`/`cast` are **not installed in the authoring environment** — all
  artifacts are authored and committed here; `forge build`, deploy, and the
  `DEMO COMPLETE` run happen in an environment with Foundry + funded keys.

---

## 2. Why Plasma collapses the Tron scope

EVM-equivalence means we deploy the **frozen vendored bytecode unchanged**.
Every "hard constraint" from the master ticket (19-step settle order, no raw
`ecrecover`, frozen typehashes, EOA signer) is satisfied **automatically**.

| Tron requirement | Plasma | Reason |
|------------------|--------|--------|
| TIP-712 `_domainSeparatorV4()` override (`& 0xffffffff`) | **removed** | OZ `EIP712Upgradeable` already reads `block.chainid` = 9746 correctly |
| TronWeb `_signTypedData` signer | **removed** | sign with `cast wallet sign` / `vm.sign` |
| `v` normalization to 27/28 | **removed** | EVM signers already canonical |
| TronBox / `tronbox.js` fallback | **removed** | Foundry only |
| TRC20 vs ERC-20 | **n/a** | standard ERC-20 |
| Base58 ↔ hex address conversion | **n/a** | native 20-byte hex |
| TVM edits to `src/` | **none** | vendor + deploy unchanged |

Source-of-truth evidence (EVM repo):
`__EIP712_init("SohoSettlement","1")` and `ECDSA.recover(_hashTypedDataV4(...))`
in `src/SohoSettlement.sol`; asset is env-driven via `script/DeployConfig.sol`.

---

## 3. Consolidated backlog (Tron → Plasma)

| # | Original (Tron) | Plasma disposition | Lands in |
|---|-----------------|--------------------|----------|
| **#1** | Master: 5-act USDT demo | Port to Plasma testnet (9746, EIP-712) | this repo |
| **#2** | Bootstrap + sync + TronWeb pkg + `tronbox.js` | **Reduced** — README/env/sync + **`foundry.toml`**; drop TronWeb + tronbox | this repo |
| **#3** | TIP-712 override + TronWeb signer | **Deleted** — folds to a 1-line `DOMAIN_SEPARATOR` assert in #4 | — |
| **#4** | Nile deploy + 5 acts (`.ts`/TronBox) | **Core** — Foundry deploy (reuse `Deploy.s.sol`) + author 5-act driver | this repo |
| **#5** | Tron docs + LINK-PACK | **Kept** — re-skinned for Plasma / Plasmascan | this repo |
| **#6** | EVM pointer doc | **Kept** — cross-link PR | `sohopay-protocol` |

**Critical path:** #2 → #4 → #5. #6 independent. #3 absorbed into #4.

---

## 4. Step-by-step plan

### Step 0 — Pre-flight spike ✅ DONE
- [x] Confirm testnet chain id (9746).
- [x] Confirm USDT decimals (6) + that testnet has no token at the mainnet address.
- [x] Decide vendored dir = `src/`; testnet asset = mock 6-dec ERC-20.

### Sub-issue #2 — Bootstrap (commit: `feat(#2): plasma bootstrap + sync`)
1. **`foundry.toml`** — `src="src"`, `libs=["lib"]`, OZ remappings, solc 0.8.24,
   `[rpc_endpoints] plasma_testnet`, `[etherscan] plasma_testnet` (Plasmascan
   verify). Set `evm_version` to a Plasma-supported fork (default `cancun`,
   **verify**; downshift to `shanghai`/`paris` if deploy rejects opcodes).
2. **`.env.example`** — `PLASMA_RPC`, `EXPECTED_CHAIN_ID=9746`,
   `USDT_ADDR=` (blank → deploy mock), deployer/agent/trusted-signer keys,
   `VAULT_NAME`/`VAULT_SYMBOL`, `FEE_RECIPIENT`, `TREASURY_SAFE`.
3. **`scripts/sync-from-evm.sh`** — retarget rsync `contracts/` → **`src/`**;
   `mkdir -p test/mocks`; run → vendors `src/`, writes real SHA to `SYNCED_FROM`.
4. **`README.md`** — re-skin to Plasma (network table, quick start, layout);
   remove Track-B / TronBox / TIP-712 language.
   - *Delete:* `package.json` TronWeb stub + `tronbox.js` (never created).
   - **Acceptance:** fresh clone + `./scripts/sync-from-evm.sh ../sohopay-protocol`
     populates `src/` and updates `SYNCED_FROM`; README links to EVM spec + proof.

### Sub-issue #3 — folded in (no standalone commit)
- Assertion in the deploy/demo: deployed proxy `DOMAIN_SEPARATOR` matches an
  off-chain EIP-712 digest at chain 9746, **before Act 3**. No override.

### Sub-issue #4 — Deploy + 5 acts (commit: `feat(#4): plasma deploy + 5-act demo`)
5. **Mock asset** — `test/mocks/MockUSDT.sol` (6-dec ERC-20, mintable) for the
   self-contained testnet demo; real token via `USDT_ADDR` env override.
6. **Deploy** — `scripts/tether-demo/deploy-plasma.sh` wrapping
   `forge script script/Deploy.s.sol --rpc-url plasma_testnet --broadcast --verify`;
   wire `USDT_ADDR` (or freshly-deployed mock); Tier-2 agent, Active merchant,
   fund vault + hot float.
7. **Act drivers** (`script/DemoPlasma.s.sol` + `cast`, not `.ts`):
   - Act 1 Setup (deploy) · Act 2 Lend (deposit USDT → `svUSDT`) ·
     Act 3 Settle (sign PaymentIntent + CreditAttestation with trusted-signer
     key, standard EIP-712; includes #3 sanity assert) ·
     Act 4 Repay (partial; overpayment reverts) ·
     Act 5 Safety (replay, caps, closed-loop, `emergencyRedeem` while paused).
8. **`scripts/tether-demo/run-plasma-demo.sh`** — orchestrates acts 1–5, prints
   `DEMO COMPLETE`.
   - **Acceptance:** one command → `DEMO COMPLETE`; merchant receives USDT on
     settle; overpayment reverts on repay.

### Sub-issue #5 — Docs + LINK-PACK (commit: `docs(#5): plasma demo docs + link-pack`)
9. **`scripts/tether-demo/extract-link-pack.sh`** — parse
   `broadcast/Deploy.s.sol/9746/run-latest.json` → emit Plasmascan links.
10. **`docs/tether-demo/`**: `CEO-RUNBOOK.md` (one-command, no Solidity),
    `DEPLOY-PLASMA.md` (faucet, XPL/USDT funding, gas/paymaster notes),
    `MEETING-GUIDE.md` (5-act narrative + Q&A),
    `LINK-PACK.md` (USDT, Settlement proxy, Vault proxy, Act 3 tx, Act 5
    `emergencyRedeem` tx, `SYNCED_FROM` SHA).
    - **Acceptance:** CEO runs from runbook alone; LINK-PACK complete.

### Sub-issue #6 — EVM pointer doc (commit in `../sohopay-protocol`, separate PR)
11. Branch in `sohopay-protocol`; add `docs/tether-demo/PLASMA-REPO.md` +
    one-line cross-link; disclaimer "demo only, not production Plasma support".
    PR lands **there**, not here.
    - ⚠️ `docs/tether-demo/` does not yet exist upstream (`develop` has
      `docs/usdt-demo-plan.md`) — create the folder.

---

## 5. Verification (maps to #1 success criteria)

| Criterion | How |
|-----------|-----|
| Contracts deployed on Plasma | `forge script … --broadcast --verify`; Plasmascan |
| `run-plasma-demo.sh` → `DEMO COMPLETE` | one command |
| Merchant receives USDT on settle | balance assert in Act 3 |
| Overpayment reverts on repay | expect-revert in Act 4 |
| LINK-PACK complete | `extract-link-pack.sh` output |
| `SYNCED_FROM` pins commit | written by `sync-from-evm.sh` |

**Requires the operator's environment:** Foundry installed, funded deployer
(XPL via faucet), private keys in `.env`. Build/deploy are not run in the
authoring environment.

---

## 6. Risks

| Risk | Mitigation |
|------|------------|
| `evm_version=cancun` opcodes unsupported on Plasma | verify; downshift to `shanghai`/`paris` |
| Real testnet USDT0 address unknown | mock 6-dec ERC-20 default; `USDT_ADDR` override |
| Gas model (XPL vs USDT paymaster) | document both in `DEPLOY-PLASMA.md` |
| Upstream `script/DemoUSDT.s.sol` does not exist | 5-act driver authored from spec |
| `docs/tether-demo/` missing upstream (#6) | create folder in cross-link PR |

---

## 7. Commit cadence

One commit per completed sub-issue: plan doc → #2 → #4 → #5 → #6 (separate repo).
Branch: `sohopay-protocol-plasma-implementation-01`.
