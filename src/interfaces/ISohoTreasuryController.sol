// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title  ISohoTreasuryController — Soho-specific surface of SohoTreasuryController (spec §5 / §5.1)
/// @notice Treasury authority: an OZ TimelockController that also holds UUPS upgrade
///         authorization (D14) and the sole cold→hot custody path (D-CUSTODY).
/// @dev    The bulk of this contract's surface is OZ `TimelockController`
///         (schedule / scheduleBatch / execute / cancel / role admin) and is NOT redeclared
///         here — integrators use the OZ ABI for those. This interface declares only the
///         Soho-specific addition the system calls cross-contract. Spec §5 is prose; the
///         shape below is the minimal faithful interpretation (see docs/DECISIONS.md
///         D-IFACE-5). No Types.* type appears here.
interface ISohoTreasuryController {
    /// @notice Sole cold→hot path: move `amount` USDC from custody into the settlement hot
    ///         float. Reverts if the resulting hot balance would exceed `hotFloatCeiling`.
    ///         Restricted to WARM_REFILL_ROLE (D-CUSTODY).
    function refillHotFloat(uint256 amount) external;

    // ===== EVENTS =====
    event HotFloatRefilled(uint256 amount);
}
