// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";
import {ISohoEvents} from "../interfaces/ISohoEvents.sol";
import {AlreadyRegistered, InvalidStatusTransition} from "./RegistryErrors.sol";

/// @title  MerchantRegistry (abstract module — inherited by SohoSettlement)
/// @notice Treasury-gated merchant registry (v1: no self-serve onboarding). The payout
///         side of closed-loop settlement (D-CLOSEDLOOP): settlement pays only a
///         registered, Active merchant's stored payout address (spec §3.1 steps 9 & 17).
/// @dev    Graduates to its own deployment only when onboarding goes permissionless
///         (KYB / fee tiers / disputes) — explicitly out of v1 scope.
///
///         Single-asset v1: the Merchant struct has no asset field (asset is implied USDC),
///         so registration takes NO `preferredAsset` param — matching the spec §3 interface
///         `registerMerchant(bytes32, address, uint96)`. (The earlier skeleton's stray
///         `preferredAsset` arg was a pre-Rev-5 multi-asset leftover; removed. See
///         docs/DECISIONS.md D-MERCH-ASSET.)
///
///         Error taxonomy per docs/DECISIONS.md D-ERRTAX-1: (1) shared Types.sol errors;
///         (2) registry-local semantic errors below; (3) generic guards. Tagged at sites.
abstract contract MerchantRegistry is ISohoEvents {
    // registry-local errors (class 2) live in RegistryErrors.sol — see import above.
    // events live in ISohoEvents (single declaration site) — see import above.
    mapping(bytes32 => Types.Merchant) internal _merchants;

    function _registerMerchant(bytes32 merchantId, address payout, uint96 dailyCap) internal {
        if (payout == address(0)) revert Types.ZeroAddress(); // (1)
        if (_merchants[merchantId].status != Types.Status.None) revert AlreadyRegistered(merchantId); // (2)
        _merchants[merchantId] = Types.Merchant({
            payout: payout, dailyCap: dailyCap, dailySpent: 0, windowStart: 0, status: Types.Status.Active
        });
        emit MerchantRegistered(merchantId, payout);
    }

    function _setMerchantStatus(bytes32 merchantId, Types.Status s) internal {
        // Merchants are only ever Active/Paused (Revoked/Defaulted are agent-only states).
        // Pause via GUARDIAN, unpause via TREASURY — role split enforced at the call site.
        Types.Merchant storage m = _merchants[merchantId];
        Types.Status from = m.status;
        if (from == Types.Status.None) revert Types.MerchantNotActive(merchantId); // (1) no such merchant
        if (s != Types.Status.Active && s != Types.Status.Paused) {
            revert InvalidStatusTransition(uint8(from), uint8(s)); // (2) non-operational target
        }
        m.status = s;
        emit MerchantStatusChanged(merchantId, s);
    }

    function _setMerchantPayout(bytes32 merchantId, address newPayout) internal {
        // TREASURY_ROLE at call site. Allowed while Paused (redirect a compromised payout
        // without unpausing). Emits old+new for the payout-redirection audit trail.
        Types.Merchant storage m = _merchants[merchantId];
        if (m.status == Types.Status.None) revert Types.MerchantNotActive(merchantId); // (1) no such merchant
        if (newPayout == address(0)) revert Types.ZeroAddress(); // (1)
        address oldPayout = m.payout;
        m.payout = newPayout;
        emit MerchantPayoutChanged(merchantId, oldPayout, newPayout);
    }

    function getMerchant(bytes32 merchantId) public view virtual returns (Types.Merchant memory) {
        return _merchants[merchantId];
    }
}
