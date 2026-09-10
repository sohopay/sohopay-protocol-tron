// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";

/// @title  CapManager (abstract module — inherited by SohoSettlement)
/// @notice On-chain cap enforcement: per-tier ceilings, per-agent / per-merchant / global
///         rolling daily windows. THE SECOND INDEPENDENT GATE (plan D5).
/// @dev    block.timestamp ONLY — never block.number (Phase-2 EVM portability: block
///         times range 0.25s-12s across chains; a block-based window silently changes
///         cap semantics per chain). Window roll: if now >= windowStart + 1 days, reset
///         spent and set windowStart = now (fixed window; documented choice — a true
///         sliding window costs more storage for marginal benefit at v1 scale).
///         INV-4 / INV-11 live here.
abstract contract CapManager {
    struct TierCeiling {
        uint96 perTx;
        uint96 daily;
    }

    mapping(uint8 => TierCeiling) internal _tierCeilings; // Treasury-set upper bounds
    uint96 internal _globalDailyCap;
    uint96 internal _globalDailySpent;
    uint64 internal _globalWindowStart;

    /// @dev Fixed rolling-window length. block.timestamp only (never block.number).
    uint64 internal constant WINDOW = 1 days;

    /// @dev Scope tags for DailyCapExceeded(bytes32). Short ASCII, right-padded.
    bytes32 internal constant SCOPE_AGENT = "AGENT";
    bytes32 internal constant SCOPE_MERCHANT = "MERCHANT";
    bytes32 internal constant SCOPE_GLOBAL = "GLOBAL";

    // Dedicated, richer cap events (the spec's generic CapUpdated lives in ISohoEvents;
    // CapManager emits these instead — see docs/DECISIONS.md D-EVENTS-1).
    event TierCeilingSet(uint8 indexed tier, uint96 perTx, uint96 daily);
    event GlobalDailyCapSet(uint96 cap);

    /// @dev Settlement step 13. MUST execute inside the effects phase (after paymentId
    ///      consumption, before transfers) so spent-accounting and consumption are atomic.
    ///      Reverts: PerTxCapExceeded / DailyCapExceeded(scope).
    ///      Sums are computed in uint256 so a near-overflow yields the correct cap error
    ///      rather than an arithmetic panic; accrual back into uint96 is safe because each
    ///      checked sum is <= its cap <= type(uint96).max.
    function _checkAndAccrueCaps(Types.Agent storage agent, Types.Merchant storage merchant, uint96 amount)
        internal
    {
        _checkCaps(agent, merchant, amount);
        _accrueCaps(agent, merchant, amount);
    }

    /// @dev Effective spent for a window: 0 if the window has rolled (now >= start + WINDOW),
    ///      else the stored spent. Lets the step-13 CHECK reason about post-roll spend without
    ///      mutating storage (the matching roll is persisted later in _accrueCaps).
    function _effectiveSpent(uint96 spent, uint64 windowStart) private view returns (uint96) {
        return block.timestamp >= uint256(windowStart) + WINDOW ? 0 : spent;
    }

    /// @dev Settlement step 13 — per-tx + per-agent/merchant/global daily windows. CHECK ONLY
    ///      (no state change) so it can sit in the checks phase, strictly before effects.
    ///      Sums in uint256 so a near-overflow yields the correct cap error, not a panic.
    function _checkCaps(Types.Agent storage agent, Types.Merchant storage merchant, uint96 amount)
        internal
        view
    {
        if (amount > agent.perTxCap) revert Types.PerTxCapExceeded(amount, agent.perTxCap);
        if (uint256(_effectiveSpent(agent.dailySpent, agent.windowStart)) + amount > agent.dailyCap) {
            revert Types.DailyCapExceeded(SCOPE_AGENT);
        }
        if (uint256(_effectiveSpent(merchant.dailySpent, merchant.windowStart)) + amount > merchant.dailyCap)
        {
            revert Types.DailyCapExceeded(SCOPE_MERCHANT);
        }
        if (uint256(_effectiveSpent(_globalDailySpent, _globalWindowStart)) + amount > _globalDailyCap) {
            revert Types.DailyCapExceeded(SCOPE_GLOBAL);
        }
    }

    /// @dev Settlement step 16 — roll each window if elapsed, then add `amount`. Safe to add
    ///      into uint96 because _checkCaps proved each post-roll sum <= cap <= uint96 max.
    ///      MUST run in the effects phase (after paymentId consumption, before transfers).
    /// @dev A2A settlement — payer + global daily windows only. No merchant storage.
    ///      CHECK ONLY (no state change). Same uint256-sum overflow hygiene as _checkCaps.
    function _checkPayerCaps(Types.Agent storage payer, uint96 amount) internal view {
        if (amount > payer.perTxCap) revert Types.PerTxCapExceeded(amount, payer.perTxCap);
        if (uint256(_effectiveSpent(payer.dailySpent, payer.windowStart)) + amount > payer.dailyCap) {
            revert Types.DailyCapExceeded(SCOPE_AGENT);
        }
        if (uint256(_effectiveSpent(_globalDailySpent, _globalWindowStart)) + amount > _globalDailyCap) {
            revert Types.DailyCapExceeded(SCOPE_GLOBAL);
        }
    }

    /// @dev A2A settlement — roll payer + global windows, then add `amount`. Does not
    ///      touch merchant daily windows. Safe to add into uint96 because _checkPayerCaps
    ///      proved each post-roll sum <= cap <= uint96 max.
    function _accruePayerCaps(Types.Agent storage payer, uint96 amount) internal {
        uint64 nowTs = uint64(block.timestamp);
        if (block.timestamp >= uint256(payer.windowStart) + WINDOW) {
            payer.windowStart = nowTs;
            payer.dailySpent = amount;
        } else {
            payer.dailySpent += amount;
        }
        if (block.timestamp >= uint256(_globalWindowStart) + WINDOW) {
            _globalWindowStart = nowTs;
            _globalDailySpent = amount;
        } else {
            _globalDailySpent += amount;
        }
    }

    function _accrueCaps(Types.Agent storage agent, Types.Merchant storage merchant, uint96 amount) internal {
        uint64 nowTs = uint64(block.timestamp);
        if (block.timestamp >= uint256(agent.windowStart) + WINDOW) {
            agent.windowStart = nowTs;
            agent.dailySpent = amount;
        } else {
            agent.dailySpent += amount;
        }
        if (block.timestamp >= uint256(merchant.windowStart) + WINDOW) {
            merchant.windowStart = nowTs;
            merchant.dailySpent = amount;
        } else {
            merchant.dailySpent += amount;
        }
        if (block.timestamp >= uint256(_globalWindowStart) + WINDOW) {
            _globalWindowStart = nowTs;
            _globalDailySpent = amount;
        } else {
            _globalDailySpent += amount;
        }
    }

    function _setTierCeilings(uint8 tier, uint96 perTx, uint96 daily) internal {
        // TREASURY_ROLE at call site. Raising goes through timelock, lowering immediate
        // (INV-11) — that policy is enforced in TreasuryController, not here; this setter
        // unconditionally writes, so cap lowering always succeeds.
        _tierCeilings[tier] = TierCeiling({perTx: perTx, daily: daily});
        emit TierCeilingSet(tier, perTx, daily);
    }

    function _setGlobalDailyCap(uint96 cap) internal {
        _globalDailyCap = cap;
        emit GlobalDailyCapSet(cap);
    }

    // ── Global cumulative outstanding-exposure cap (D5 / I5) — bounds TOTAL on-the-hook,
    //    not just daily flow. The backstop against a slow signer compromise. ──
    uint96 internal _globalOutstanding;
    uint96 internal _globalOutstandingCap;

    event GlobalOutstandingCapSet(uint96 cap);

    /// @dev Settlement step 13 cumulative check. Reverts GlobalCumulativeCapExceeded.
    ///      Accrued in effects (step 16) and decremented on repay/default write-down.
    function _checkGlobalOutstanding(uint96 amountPlusFee) internal view {
        if (uint256(_globalOutstanding) + amountPlusFee > _globalOutstandingCap) {
            revert Types.GlobalCumulativeCapExceeded();
        }
    }

    function _accrueOutstanding(uint96 amountPlusFee) internal {
        // Safe: caller invokes _checkGlobalOutstanding first, bounding the sum by the cap.
        _globalOutstanding += amountPlusFee;
    }

    function _releaseOutstanding(uint96 amountPlusFee) internal {
        // Floor at zero — repayments/write-downs must never underflow outstanding exposure.
        uint96 outstanding = _globalOutstanding;
        _globalOutstanding = amountPlusFee >= outstanding ? 0 : outstanding - amountPlusFee;
    }

    function _setGlobalOutstandingCap(uint96 cap) internal {
        _globalOutstandingCap = cap;
        emit GlobalOutstandingCapSet(cap);
    }
}
