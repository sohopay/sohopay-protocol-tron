// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title  ISohoFirstLossReserve — external surface of SohoFirstLossReserve (spec §5)
/// @notice First-loss reserve: absorbs anonymous-book losses before lenders (I3). Its
///         balance is the anonymous-book ceiling the credit engine reads.
/// @dev    Spec §5 specifies this contract by NAMED members only ("fund, cover (vault-only),
///         balanceOf, anonymousBookCeiling (= balance), withdraw (TREASURY, timelocked)"),
///         not as a full ABI block. The single-asset (USDC) shapes below are the faithful
///         Rev-5 interpretation (see docs/DECISIONS.md D-RESERVE-1) — the WS-A skeleton's
///         multi-asset `(address asset, ...)` variants were a pre-Rev-5 leftover and are
///         dropped, mirroring D-MERCH-ASSET. `setVault` + fund-movement events are added so
///         the reconciliation pipeline / indexer have an accurate surface (Gate-1: no stale
///         ABI). No Types.* type appears here.
interface ISohoFirstLossReserve {
    /// @notice Add USDC to the reserve (pulls `amount` from caller). Permissionless.
    function fund(uint256 amount) external;

    /// @notice Cover a loss from reserve funds; callable only by the vault. Returns the
    ///         amount actually covered (min(amount, balance)), transferred to the vault.
    function cover(uint256 amount) external returns (uint256 covered);

    /// @notice Current reserve balance (USDC backing first-loss coverage).
    function balanceOf() external view returns (uint256);

    /// @notice Anonymous-book exposure ceiling read by the credit engine (I3) — equals the
    ///         reserve balance.
    function anonymousBookCeiling() external view returns (uint256);

    /// @notice Withdraw reserve funds; TREASURY-only, timelocked.
    function withdraw(uint256 amount, address to) external;

    /// @notice Wire the sole `cover` caller (the vault); TREASURY-only.
    function setVault(address vault) external;

    // ===== EVENTS =====
    event Funded(address indexed from, uint256 amount);
    event LossCovered(uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event VaultSet(address vault);
}
