// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title  ISohoVault — external surface of SohoVault (spec §4)
/// @notice Single USDC ERC-4626 vault: withdrawal queue, per-epoch instant allowance,
///         pause-independent emergency exit (D15), and the credit-side hooks only
///         SohoSettlement may call. Transcribed from spec §4.
/// @dev    The deployed vault also exposes the full standard ERC-4626 surface
///         (IERC4626Upgradeable: deposit/mint/withdraw/redeem/totalAssets/...); this
///         interface lists only the Soho-specific additions, exactly as spec §4 does.
///         No Types.* struct/enum appears in these signatures, so Types.sol is not
///         imported here.
interface ISohoVault {
    /* is IERC4626Upgradeable */
    // ===== Withdrawal queue =====
    function requestRedeem(uint256 shares, address receiver) external returns (uint256 id);
    function claimRedeem(uint256 id) external returns (uint256 assets); // claim-time price (D9)
    function cancelRedeem(uint256 id) external; // share-lock until cooldown (O7)
    function instantRedeemAllowance(address owner) external view returns (uint256); // per-epoch (O5)

    // ===== EMERGENCY EXIT (D15) — works even when settlement is paused; pro-rata on idle liquidity =====
    function emergencyRedeem(uint256 shares, address receiver) external returns (uint256 assets);

    // ===== Credit-side hooks (only SohoSettlement) =====
    function fundSettlement(uint256 amount) external;
    function receiveRepayment(uint256 amount, bytes32 agentId) external;
    function recognizeLoss(uint256 amount, bytes32 agentId) external; // reserve covers first (I3)

    // ===== Config (TREASURY); pause via GUARDIAN =====
    function setDepositCap(uint256 cap) external;
    function setCooldown(uint64 secs) external; // must exceed markDefault timelock delay
    function setInstantAllowance(uint96 perEpoch) external; // O5: per-account-per-epoch instant cap (0 == queue-only)
    function setSettlement(address settlement) external; // wiring (sole credit-hook caller)
    function setFirstLossReserve(address reserve) external; // wiring (loss cover source)

    // ===== EVENTS =====
    event RedeemRequested(uint256 indexed id, address indexed owner, uint256 shares);
    event RedeemClaimed(uint256 indexed id, uint256 shares, uint256 assets);
    event RedeemCancelled(uint256 indexed id);
    event EmergencyRedeemed(address indexed owner, uint256 shares, uint256 assets);
    event SettlementFunded(uint256 amount);
    event RepaymentApplied(bytes32 indexed agentId, uint256 amount);
    event LossRecognized(
        bytes32 indexed agentId, uint256 gross, uint256 reserveCovered, uint256 lenderImpact
    );
    // config events
    event DepositCapSet(uint256 cap);
    event CooldownSet(uint64 secs);
    event InstantAllowanceSet(uint96 perEpoch);
    event SettlementSet(address settlement);
    event FirstLossReserveSet(address reserve);
}
