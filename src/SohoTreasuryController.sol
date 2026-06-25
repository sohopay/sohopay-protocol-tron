// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Types} from "./libraries/Types.sol";
import {ISohoSettlement} from "./interfaces/ISohoSettlement.sol";

/// @title  SohoTreasuryController
/// @notice Governance shim over OZ TimelockController, owned by the Treasury Safe (3-of-5
///         cold). Holds TREASURY_ROLE / DEFAULT_ADMIN on the other contracts, so all
///         non-emergency parameter changes pass through one 48h timelock and event stream.
/// @dev    Direction-sensitive rules (spec §6):
///         - RAISING any cap/ceiling: timelocked (schedule -> 48h -> execute, via address(this))
///         - LOWERING a cap: immediate (emergency-safe direction; INV-11) — admin (Safe)
///         - markDefault: its OWN shorter delay (O2 — must be < vault cooldown so the default
///           lands before queued withdrawals can front-run it). Implemented as a dedicated
///           schedule/execute path, NOT the 48h queue (OZ forbids delay < minDelay).
///         D-CUSTODY: refillHotFloat is the cold->hot path (WARM_REFILL_ROLE or Treasury),
///         bounded by hotFloatCeiling so a compromised warm key can never overfund.
///
///         DECISION(gate-1): controller is IMMUTABLE (OZ-audited TimelockController; no UUPS).
///
///         INV-8 note: the canonical guard (no address holds GUARDIAN_ROLE and is a trusted
///         attestation signer) lives in SohoSettlement (enforced both directions, committed).
///         At this governance layer the analog is enforced here: WARM_REFILL_ROLE (fast funds)
///         and CANCELLER_ROLE (emergency cancel) are mutually exclusive on role grants — one
///         key must never hold both powers. See docs/DECISIONS.md D-CONTROLLER-1.
contract SohoTreasuryController is TimelockController {
    using SafeERC20 for IERC20;

    bytes32 public constant WARM_REFILL_ROLE = keccak256("WARM_REFILL_ROLE");

    IERC20 public immutable usdc;
    uint64 public immutable markDefaultDelay; // O2: dedicated short delay (< minDelay, < vault cooldown)

    address public settlement; // hot-float target + markDefault target
    uint96 public hotFloatCeiling; // D-CUSTODY: max USDC that may sit in settlement's reach
    mapping(bytes32 => uint256) public markDefaultEta; // agentId => earliest execute time

    event HotFloatRefilled(uint256 amount, uint256 newHotBalance, address by);
    event HotFloatCeilingSet(uint96 ceiling);
    event SettlementSet(address settlement);
    event MarkDefaultScheduled(bytes32 indexed agentId, uint256 eta);
    event MarkDefaultExecuted(bytes32 indexed agentId);

    error HotFloatCeilingExceeded(uint256 resultingHotBalance, uint96 ceiling);
    error RoleOverlap(bytes32 role, address account);
    error MarkDefaultNotReady(bytes32 agentId);
    error InvalidDelay();

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin,
        IERC20 usdc_,
        uint64 markDefaultDelay_,
        uint96 hotFloatCeiling_
    ) TimelockController(minDelay, proposers, executors, admin) {
        if (address(usdc_) == address(0)) revert Types.ZeroAddress();
        if (markDefaultDelay_ >= minDelay) revert InvalidDelay(); // must be the SHORTER delay
        usdc = usdc_;
        markDefaultDelay = markDefaultDelay_;
        hotFloatCeiling = hotFloatCeiling_;
    }

    function setSettlement(address settlement_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (settlement_ == address(0)) revert Types.ZeroAddress();
        settlement = settlement_;
        emit SettlementSet(settlement_);
    }

    // ── D-CUSTODY: cold -> hot float refill (bounded) ──
    /// @notice Top up SohoSettlement's hot float from the controller's cold USDC, capped by
    ///         hotFloatCeiling. WARM_REFILL_ROLE (capped reach) or Treasury (admin).
    function refillHotFloat(uint256 amount) external {
        if (!hasRole(WARM_REFILL_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Types.NotAuthorized();
        }
        uint256 newHot = usdc.balanceOf(settlement) + amount;
        if (newHot > hotFloatCeiling) revert HotFloatCeilingExceeded(newHot, hotFloatCeiling);
        usdc.safeTransfer(settlement, amount); // from the controller's cold balance
        emit HotFloatRefilled(amount, newHot, msg.sender);
    }

    /// @notice Raise: timelocked (only via a scheduled op, msg.sender == address(this)).
    ///         Lower: immediate, admin (Safe) — emergency-safe direction.
    function setHotFloatCeiling(uint96 ceiling) external {
        if (ceiling > hotFloatCeiling) {
            if (msg.sender != address(this)) revert Types.NotAuthorized(); // raise must pass the 48h timelock
        } else if (msg.sender != address(this) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Types.NotAuthorized();
        }
        hotFloatCeiling = ceiling;
        emit HotFloatCeilingSet(ceiling);
    }

    // ── markDefault dual-delay (O2) — dedicated short-delay path ──
    function scheduleMarkDefault(bytes32 agentId) external onlyRole(PROPOSER_ROLE) {
        uint256 eta = block.timestamp + markDefaultDelay;
        markDefaultEta[agentId] = eta;
        emit MarkDefaultScheduled(agentId, eta);
    }

    function executeMarkDefault(bytes32 agentId) external onlyRole(EXECUTOR_ROLE) {
        uint256 eta = markDefaultEta[agentId];
        if (eta == 0 || block.timestamp < eta) revert MarkDefaultNotReady(agentId);
        delete markDefaultEta[agentId];
        ISohoSettlement(settlement).markDefault(agentId);
        emit MarkDefaultExecuted(agentId);
    }

    // ── INV-8 analog: WARM_REFILL_ROLE and CANCELLER_ROLE are mutually exclusive ──
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == WARM_REFILL_ROLE && hasRole(CANCELLER_ROLE, account)) revert RoleOverlap(role, account);
        if (role == CANCELLER_ROLE && hasRole(WARM_REFILL_ROLE, account)) revert RoleOverlap(role, account);
        return super._grantRole(role, account);
    }
}
