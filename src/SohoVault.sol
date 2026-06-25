// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Types} from "./libraries/Types.sol";
import {ISohoFirstLossReserve} from "./interfaces/ISohoFirstLossReserve.sol";
import {ISohoVault} from "./interfaces/ISohoVault.sol";

/// @title  SohoVault (single USDC ERC-4626, UUPS upgradeable — plan Rev 5)
/// @notice ONE vault (USDC only). ERC-4626 + withdrawal queue + per-account-per-epoch
///         instant path + PAUSE-INDEPENDENT EMERGENCY EXIT (D15). Default loss recognized
///         against the first-loss reserve before lenders (INV-5).
/// @dev    Virtual-share offset (INV-12). D9 claim-time pricing. SafeERC20 (USDC).
///         Upgradeable behind TreasuryController + timelock (D14); __gap reserved.
///
///         Accounting (see docs/DECISIONS.md D-VAULT-1): totalAssets = idle USDC balance +
///         `_deployedAssets` (capital lent to settlement, a receivable). fundSettlement
///         deploys (balance->settlement, receivable up), receiveRepayment unwinds it,
///         recognizeLoss writes it down (reserve covers first). This keeps share price
///         stable on deploy/repay (INV-6) and isolates lender impact to uncovered loss
///         (INV-5). Reconciliation with INV-17 (hot-float non-commingling) is pending the
///         controller/settlement custody wiring + invariant suite.
contract SohoVault is
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ISohoVault
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    mapping(uint256 => Types.RedeemRequest) public requests;
    uint256 public nextRequestId;
    uint64 public cooldown; // O4: 48h; MUST exceed markDefault timelock delay
    uint256 public depositCap; // 0 == unlimited
    uint96 public instantAllowancePerEpoch; // O5: per-account-per-epoch instant redemption (0 == queue-only)
    mapping(address => uint96) internal _epochRedeemed;
    mapping(address => uint64) internal _epochStart; // epoch index = block.timestamp / EPOCH
    uint256 internal _deployedAssets; // capital lent to settlement (receivable) — D-VAULT-1
    address public settlement; // sole caller of credit-side hooks (receiveRepayment/recognizeLoss)
    address public firstLossReserve;
    address public treasuryController; // upgrade authority + fundSettlement caller

    /// @dev O5: instant-allowance epoch length.
    uint64 internal constant EPOCH = 1 days;

    // ── D-SECURITIES-DEFENSIVE: shares are restrictable-but-unrestricted (INV-19) ──
    // Built now, DISABLED by default. If counsel later requires Reg-D-style limits, flip
    // these on WITHOUT redeploy.
    bool public transfersRestricted; // default false (open)
    mapping(address => bool) public allowedHolder; // investor registry / whitelist hook
    bool public onboardingRestricted; // default false (open lender onboarding)

    // Queue / credit / config events are declared in ISohoVault (inherited). These three are
    // the INV-19 restrictable-shares events, a vault-only defensive capability not in §4:
    event TransfersRestrictedSet(bool restricted);
    event OnboardingRestrictedSet(bool restricted);
    event HolderAllowed(address indexed holder, bool allowed);

    // ── vault-local errors ──
    error RestrictedRecipient(address account);
    error RequestNotClaimable(uint256 id);
    error NotRequestOwner(uint256 id);
    error LossExceedsDeployed(uint256 amount, uint256 deployed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 usdc_, string memory name_, string memory symbol_, address controller)
        external
        initializer
    {
        if (address(usdc_) == address(0) || controller == address(0)) revert Types.ZeroAddress();
        __ERC4626_init(usdc_);
        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, controller);
        _grantRole(Types.TREASURY_ROLE, controller);
        treasuryController = controller;
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != treasuryController) revert Types.NotAuthorized();
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6; // INV-12 virtual-share inflation defense
    }

    // ── totalAssets: idle USDC + deployed receivable (D-VAULT-1) ──
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _deployedAssets;
    }

    function deployedAssets() external view returns (uint256) {
        return _deployedAssets;
    }

    function idleLiquidity() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    // ── Deposits: cap (maxDeposit/maxMint) + pause + onboarding (_deposit) ──
    function maxDeposit(address) public view override returns (uint256) {
        if (depositCap == 0) return type(uint256).max;
        uint256 ta = totalAssets();
        return ta >= depositCap ? 0 : depositCap - ta;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        return
            maxAssets == type(uint256).max
                ? type(uint256).max
                : _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
    {
        if (onboardingRestricted && !allowedHolder[receiver]) revert RestrictedRecipient(receiver);
        super._deposit(caller, receiver, assets, shares);
    }

    // ── Instant redemption path: standard ERC-4626 redeem/withdraw, capped per epoch (O5) ──
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 allowanceShares = _convertToShares(instantRedeemAllowance(owner), Math.Rounding.Floor);
        uint256 bal = balanceOf(owner);
        return allowanceShares < bal ? allowanceShares : bal;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 allowanceAssets = instantRedeemAllowance(owner);
        uint256 balAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        return allowanceAssets < balAssets ? allowanceAssets : balAssets;
    }

    function instantRedeemAllowance(address owner) public view returns (uint256) {
        if (instantAllowancePerEpoch == 0) return 0;
        uint96 used = _epochStart[owner] == _currentEpoch() ? _epochRedeemed[owner] : 0;
        return used >= instantAllowancePerEpoch ? 0 : instantAllowancePerEpoch - used;
    }

    function _currentEpoch() internal view returns (uint64) {
        return uint64(block.timestamp / EPOCH);
    }

    /// @dev Tracks instant (non-queue) redemption usage against the per-epoch allowance.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint64 epoch = _currentEpoch();
        if (_epochStart[owner] != epoch) {
            _epochStart[owner] = epoch;
            _epochRedeemed[owner] = 0;
        }
        _epochRedeemed[owner] += uint96(assets); // assets <= allowance <= uint96 max (capped by maxWithdraw)
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // ── Withdrawal queue (spec §4; D9 claim-time pricing; O7 share-lock) ──
    function requestRedeem(uint256 shares, address receiver) external returns (uint256 id) {
        if (shares == 0) revert RequestNotClaimable(0);
        _transfer(msg.sender, address(this), shares); // escrow (lock) shares
        id = nextRequestId++;
        requests[id] = Types.RedeemRequest({
            owner: msg.sender,
            receiver: receiver,
            shares: shares,
            unlockAt: uint64(block.timestamp) + cooldown,
            claimed: false,
            cancelled: false
        });
        emit RedeemRequested(id, msg.sender, shares);
    }

    /// @notice Claim a matured redeem at claim-time price (D9). Partial fill when idle
    ///         liquidity is short: pays what's available, burns the proportional shares, and
    ///         leaves the remainder claimable later (INV-7: never pays beyond idle).
    function claimRedeem(uint256 id) external returns (uint256 assets) {
        Types.RedeemRequest storage r = requests[id];
        if (r.owner == address(0) || r.claimed || r.cancelled) revert RequestNotClaimable(id);
        if (block.timestamp < r.unlockAt) revert Types.CooldownNotElapsed(id);

        uint256 shares = r.shares;
        uint256 wanted = previewRedeem(shares); // claim-time price
        uint256 idle = idleLiquidity();

        uint256 sharesBurned;
        if (wanted <= idle) {
            assets = wanted;
            sharesBurned = shares;
            r.claimed = true;
        } else {
            // partial fill: pay all idle, burn proportional shares, keep request open
            assets = idle;
            sharesBurned = wanted == 0 ? 0 : shares.mulDiv(idle, wanted);
            r.shares = shares - sharesBurned;
        }
        if (sharesBurned > 0) _burn(address(this), sharesBurned);
        if (assets > 0) IERC20(asset()).safeTransfer(r.receiver, assets);
        emit RedeemClaimed(id, sharesBurned, assets);
    }

    /// @notice Cancel a matured request and reclaim escrowed shares. O7: shares stay locked
    ///         until the original cooldown elapses — cancelling cannot jump the queue.
    function cancelRedeem(uint256 id) external {
        Types.RedeemRequest storage r = requests[id];
        if (r.owner != msg.sender) revert NotRequestOwner(id);
        if (r.claimed || r.cancelled) revert RequestNotClaimable(id);
        if (block.timestamp < r.unlockAt) revert Types.SharesLocked(id);
        r.cancelled = true;
        uint256 shares = r.shares;
        if (shares > 0) _transfer(address(this), r.owner, shares); // return escrowed shares
        emit RedeemCancelled(id);
    }

    /// @notice EMERGENCY EXIT (D15 / INV-15) — callable regardless of pause and independent
    ///         of SohoSettlement. Burns `shares` for a pro-rata cut of IDLE liquidity so a
    ///         settlement-side pause can never trap lender access to liquid funds.
    /// @dev    This is a LIQUIDITY ESCAPE HATCH, not full redemption. It pays only the
    ///         pro-rata share of idle USDC (`idle * shares / totalSupply`); the deployed
    ///         portion is NOT paid here — that capital remains subject to the normal
    ///         repayment/loss lifecycle. For full-value redemption use the queue
    ///         (requestRedeem -> claimRedeem) once liquidity is available.
    function emergencyRedeem(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 supply = totalSupply();
        assets = supply == 0 ? 0 : idleLiquidity().mulDiv(shares, supply);
        _burn(msg.sender, shares);
        if (assets > 0) IERC20(asset()).safeTransfer(receiver, assets);
        emit EmergencyRedeemed(msg.sender, shares, assets);
    }

    // ── Credit-side hooks ──
    /// @dev D-CUSTODY: controller-only. Settlement can NEVER pull funds to itself; only the
    ///      TreasuryController moves vault->settlement. Deploys lender capital (receivable).
    function fundSettlement(uint256 amount) external {
        if (msg.sender != treasuryController) revert Types.NotAuthorized();
        _deployedAssets += amount;
        IERC20(asset()).safeTransfer(settlement, amount); // reverts if idle < amount
        emit SettlementFunded(amount);
    }

    /// @dev settlement-only. USDC already delivered to the vault by settlement.repay() before
    ///      this call; here we just unwind the receivable. Excess over principal is yield.
    function receiveRepayment(uint256 amount, bytes32 agentId) external {
        if (msg.sender != settlement) revert Types.NotAuthorized();
        uint256 reduce = amount > _deployedAssets ? _deployedAssets : amount;
        _deployedAssets -= reduce;
        emit RepaymentApplied(agentId, amount);
    }

    /// @dev settlement-only. Reserve covers first (INV-5): lenderImpact == 0 while the
    ///      uncovered loss is within reserve. Share price is non-decreasing absent this call
    ///      (INV-6).
    function recognizeLoss(uint256 amount, bytes32 agentId) external {
        if (msg.sender != settlement) revert Types.NotAuthorized();
        if (amount > _deployedAssets) revert LossExceedsDeployed(amount, _deployedAssets);
        uint256 covered = ISohoFirstLossReserve(firstLossReserve).cover(amount); // reserve sends `covered` USDC here
        uint256 lenderImpact = amount - covered;
        _deployedAssets -= amount;
        emit LossRecognized(agentId, amount, covered, lenderImpact);
    }

    // ── Config ──
    function setDepositCap(uint256 c) external onlyRole(Types.TREASURY_ROLE) {
        depositCap = c;
        emit DepositCapSet(c);
    }

    function setCooldown(uint64 s) external onlyRole(Types.TREASURY_ROLE) {
        cooldown = s; // must exceed markDefault timelock delay (enforced operationally)
        emit CooldownSet(s);
    }

    function setInstantAllowance(uint96 perEpoch) external onlyRole(Types.TREASURY_ROLE) {
        instantAllowancePerEpoch = perEpoch;
        emit InstantAllowanceSet(perEpoch);
    }

    function setSettlement(address s) external onlyRole(Types.TREASURY_ROLE) {
        if (s == address(0)) revert Types.ZeroAddress();
        settlement = s;
        emit SettlementSet(s);
    }

    function setFirstLossReserve(address r) external onlyRole(Types.TREASURY_ROLE) {
        if (r == address(0)) revert Types.ZeroAddress();
        firstLossReserve = r;
        emit FirstLossReserveSet(r);
    }

    function pauseDeposits() external onlyRole(Types.GUARDIAN_ROLE) {
        _pause();
    }

    function unpauseDeposits() external onlyRole(Types.TREASURY_ROLE) {
        _unpause();
    }

    // ── D-SECURITIES-DEFENSIVE setters (INV-19) ──
    function setTransfersRestricted(bool r) external onlyRole(Types.TREASURY_ROLE) {
        transfersRestricted = r;
        emit TransfersRestrictedSet(r);
    }

    function setOnboardingRestricted(bool r) external onlyRole(Types.TREASURY_ROLE) {
        onboardingRestricted = r;
        emit OnboardingRestrictedSet(r);
    }

    function setAllowedHolder(address h, bool ok) external onlyRole(Types.TREASURY_ROLE) {
        allowedHolder[h] = ok;
        emit HolderAllowed(h, ok);
    }

    /// @dev INV-19 restrictable-shares hook. While `transfersRestricted`, only allowed holders
    ///      may RECEIVE shares. Mint (from==0), burn (to==0), and queue escrow to/from the
    ///      vault are always permitted. DEFAULT-OFF — no restriction on day one.
    function _update(address from, address to, uint256 value) internal override {
        if (
            transfersRestricted && from != address(0) && to != address(0) && from != address(this)
                && to != address(this) && !allowedHolder[to]
        ) {
            revert RestrictedRecipient(to);
        }
        super._update(from, to, value);
    }

    uint256[40] private __gap;
}
