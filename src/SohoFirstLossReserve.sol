// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Types} from "./libraries/Types.sol";
import {ISohoFirstLossReserve} from "./interfaces/ISohoFirstLossReserve.sol";

/// @title  SohoFirstLossReserve (single USDC, UUPS upgradeable — plan Rev 5)
/// @notice Protocol first-loss capital. Written down BEFORE lender shares on recognized
///         defaults (INV-5). Its balance IS the anonymous-book ceiling (I3/I4): the credit
///         engine reads anonymousBookCeiling() and never lets tiers 0-2 outstanding exceed
///         it — so even 100% anonymous default cannot touch lender principal.
/// @dev    Single asset (USDC), matching Rev 5 (the skeleton's multi-asset `(address asset)`
///         variants were a pre-Rev-5 leftover — see docs/DECISIONS.md D-RESERVE-1).
///         DECISION(gate-1): reserve is UPGRADEABLE (holds funds) behind the
///         TreasuryController timelock; the controller stays immutable (recommended default).
contract SohoFirstLossReserve is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ISohoFirstLossReserve
{
    using SafeERC20 for IERC20;

    IERC20 public usdc;
    address public vault; // sole cover() caller
    address public treasuryController; // upgrade authority (D14)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 usdc_, address controller) external initializer {
        if (address(usdc_) == address(0) || controller == address(0)) revert Types.ZeroAddress();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, controller);
        _grantRole(Types.TREASURY_ROLE, controller);
        usdc = usdc_;
        treasuryController = controller;
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != treasuryController) revert Types.NotAuthorized();
    }

    /// @notice Anyone may fund (yield waterfall + manual top-ups).
    function fund(uint256 amount) external {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice Vault-only. Covers up to the reserve balance and transfers the covered amount
    ///         to the vault; returns how much was covered (INV-5: lenders only impacted past
    ///         the reserve).
    function cover(uint256 amount) external returns (uint256 covered) {
        if (msg.sender != vault) revert Types.NotAuthorized();
        uint256 bal = usdc.balanceOf(address(this));
        covered = amount > bal ? bal : amount;
        if (covered > 0) usdc.safeTransfer(vault, covered);
        emit LossCovered(covered);
    }

    function balanceOf() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice Read by the credit engine to enforce I3/I4 off-chain (= reserve balance).
    function anonymousBookCeiling() external view returns (uint256) {
        return balanceOf();
    }

    /// @notice TREASURY only, and only via the TreasuryController timelock.
    function withdraw(uint256 amount, address to) external onlyRole(Types.TREASURY_ROLE) {
        if (to == address(0)) revert Types.ZeroAddress();
        usdc.safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    function setVault(address vault_) external onlyRole(Types.TREASURY_ROLE) {
        if (vault_ == address(0)) revert Types.ZeroAddress();
        vault = vault_;
        emit VaultSet(vault_);
    }

    /// @dev Upgrade-safety storage gap (D14). Append above; never reorder.
    uint256[40] private __gap;
}
