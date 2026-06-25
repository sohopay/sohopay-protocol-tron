// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {SohoTreasuryController} from "../src/SohoTreasuryController.sol";
import {SohoSettlement} from "../src/SohoSettlement.sol";
import {SohoVault} from "../src/SohoVault.sol";
import {SohoFirstLossReserve} from "../src/SohoFirstLossReserve.sol";
import {Types} from "../src/libraries/Types.sol";
import {DeployConfig} from "./DeployConfig.sol";

/// @title  Deploy
/// @notice CREATE2 deterministic deployment (plan §7; Phase-2 address parity). Order:
///         immutable TreasuryController → UUPS implementations → ERC1967 proxies →
///         `initialize` through the controller → wire cross-refs + USDC + feeRecipient +
///         first trustedSigner + role grants + Stage-0 caps → revoke ALL deployer roles.
///         Single USDC vault; no USDT; no router. All addresses/params from `DeployConfig`.
///
/// @dev    WHY WIRING GOES THROUGH THE TIMELOCK. The proxies bake the controller in as both
///         role-admin and upgrade authority at `initialize` (no setter — D14), so from genesis
///         the ONLY holder of TREASURY_ROLE / DEFAULT_ADMIN on the proxies is the controller.
///         The deployer therefore configures the system by driving the controller, using OZ's
///         documented bootstrap-admin pattern: the controller is constructed with the deployer
///         as the optional `admin` (and the Treasury Safe as proposer/executor/canceller). The
///         deployer self-grants PROPOSER+EXECUTOR, schedules+executes the wiring batch, then
///         renounces every controller role — leaving only the Safe. This is exactly spec §7's
///         "wiring → revoke all deployer roles": the deployer never holds a role on the proxies,
///         and holds controller roles only transiently. DECISION(gate-1): controller IMMUTABLE.
///
/// @dev    PHASES (env `DEPLOY_PHASE`). The 48h timelock means the schedule and execute legs
///         CANNOT be broadcast in one transaction batch on a live chain, so `run()` branches:
///           - "all"      (default): deploy → schedule → `vm.warp(minDelay)` → execute → renounce,
///                        in one in-memory run. For tests / anvil / a short-MIN_DELAY testnet.
///                        Not broadcastable live: the warp does not move a real chain's clock, so
///                        a broadcast re-simulation of execute-after-schedule reverts (by design).
///           - "schedule" (live, leg 1): deploy + schedule the wiring batch. Record the printed
///                        proxy addresses; the deployer KEEPS its controller roles until leg 2.
///           - "execute"  (live, leg 2, after `minDelay`): load the recorded addresses from env,
///                        execute the (deterministically rebuilt) batch, then hand admin to the
///                        Safe and renounce all deployer roles. Same predecessor+salt ⇒ same op id.
contract Deploy is Script {
    SohoTreasuryController public controller;
    SohoSettlement public settlement;
    SohoVault public vault;
    SohoFirstLossReserve public reserve;
    address public settlementImpl;
    address public vaultImpl;
    address public reserveImpl;

    function run() external {
        DeployConfig.Cfg memory c = DeployConfig.load();
        _preflight(c);

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        string memory phase = vm.envOr("DEPLOY_PHASE", string("all"));
        bytes32 phaseHash = keccak256(bytes(phase));

        if (phaseHash == keccak256("execute")) {
            // live leg 2: addresses come from leg 1's recorded output.
            _loadDeployed();
            vm.startBroadcast(pk);
            _executeAndHandoff(c, deployer);
            vm.stopBroadcast();
            _log(deployer, phaseHash);
            return;
        }

        // "all" and "schedule" both deploy + schedule.
        vm.startBroadcast(pk);
        _deployContracts(c, deployer);
        _bootstrapAndSchedule(c, deployer);
        if (phaseHash != keccak256("schedule")) {
            // "all": pass the timelock in-memory and finish in one run (tests / anvil only).
            vm.warp(block.timestamp + c.minDelay + 1);
            _executeAndHandoff(c, deployer);
        }
        vm.stopBroadcast();

        _log(deployer, phaseHash);
    }

    /// @dev Live leg 2 input: the proxy/controller addresses printed by leg 1's `_log`.
    function _loadDeployed() internal {
        controller = SohoTreasuryController(payable(vm.envAddress("CONTROLLER_ADDR")));
        settlement = SohoSettlement(vm.envAddress("SETTLEMENT_ADDR"));
        vault = SohoVault(vm.envAddress("VAULT_ADDR"));
        reserve = SohoFirstLossReserve(vm.envAddress("RESERVE_ADDR"));
        settlementImpl = vm.envOr("SETTLEMENT_IMPL", address(0));
        vaultImpl = vm.envOr("VAULT_IMPL", address(0));
        reserveImpl = vm.envOr("RESERVE_IMPL", address(0));
    }

    // ── preflight: launch-critical hygiene the contracts also enforce, failed fast & loud ──
    function _preflight(DeployConfig.Cfg memory c) internal pure {
        require(c.usdc != address(0), "usdc=0");
        require(c.treasurySafe != address(0), "safe=0");
        require(c.feeRecipient != address(0), "feeRecipient=0");
        require(c.firstTrustedSigner != address(0), "trustedSigner=0");
        require(c.executor != address(0), "executor=0");
        require(c.creditAdmin != address(0), "creditAdmin=0");
        require(c.guardian != address(0), "guardian=0");
        // INV-8: no address is both GUARDIAN and a trusted attestation signer.
        require(c.firstTrustedSigner != c.guardian, "INV-8: signer==guardian");
        // Controller D-CONTROLLER-1: WARM_REFILL and CANCELLER (== Safe) are mutually exclusive.
        require(c.warmRefill != c.treasurySafe, "warmRefill==safe(canceller)");
        // O2/O4: markDefault delay strictly below both the timelock min delay and vault cooldown.
        require(c.markDefaultDelay < c.minDelay, "markDefaultDelay>=minDelay");
        require(c.cooldown > c.markDefaultDelay, "cooldown<=markDefaultDelay");
    }

    // ── 1. controller (immutable) → 2-4. impls + ERC1967 proxies, initialized to controller ──
    function _deployContracts(DeployConfig.Cfg memory c, address deployer) internal {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = c.treasurySafe;
        executors[0] = c.treasurySafe;

        controller = new SohoTreasuryController{salt: DeployConfig.saltFor(c.salt, "CONTROLLER")}(
            c.minDelay, proposers, executors, deployer, IERC20(c.usdc), c.markDefaultDelay, c.hotFloatCeiling
        );

        // reserve (UUPS) — initialize binds the controller as admin + upgrade authority.
        reserveImpl = address(new SohoFirstLossReserve{salt: DeployConfig.saltFor(c.salt, "RESERVE_IMPL")}());
        reserve = SohoFirstLossReserve(
            address(
                new ERC1967Proxy{salt: DeployConfig.saltFor(c.salt, "RESERVE_PROXY")}(
                    reserveImpl,
                    abi.encodeCall(SohoFirstLossReserve.initialize, (IERC20(c.usdc), address(controller)))
                )
            )
        );

        // vault (UUPS)
        vaultImpl = address(new SohoVault{salt: DeployConfig.saltFor(c.salt, "VAULT_IMPL")}());
        vault = SohoVault(
            address(
                new ERC1967Proxy{salt: DeployConfig.saltFor(c.salt, "VAULT_PROXY")}(
                    vaultImpl,
                    abi.encodeCall(
                        SohoVault.initialize,
                        (IERC20(c.usdc), c.vaultName, c.vaultSymbol, address(controller))
                    )
                )
            )
        );

        // settlement (UUPS) — needs the vault address at init.
        settlementImpl = address(new SohoSettlement{salt: DeployConfig.saltFor(c.salt, "SETTLEMENT_IMPL")}());
        settlement = SohoSettlement(
            address(
                new ERC1967Proxy{salt: DeployConfig.saltFor(c.salt, "SETTLEMENT_PROXY")}(
                    settlementImpl,
                    abi.encodeCall(
                        SohoSettlement.initialize,
                        (address(controller), c.usdc, address(vault), c.feeRecipient)
                    )
                )
            )
        );
    }

    // ── leg 1: deployer (bootstrap admin) configures the controller + schedules the batch ──
    function _bootstrapAndSchedule(DeployConfig.Cfg memory c, address deployer) internal {
        // bootstrap: admin self-grants the proposer/executor powers needed for the batch.
        controller.grantRole(controller.PROPOSER_ROLE(), deployer);
        controller.grantRole(controller.EXECUTOR_ROLE(), deployer);

        // controller-local config (admin, immediate — not a proxy setter, no timelock needed).
        controller.setSettlement(address(settlement));
        if (c.warmRefill != address(0)) {
            controller.grantRole(controller.WARM_REFILL_ROLE(), c.warmRefill);
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _wiringBatch(c);
        controller.scheduleBatch(targets, values, payloads, bytes32(0), c.salt, c.minDelay);
    }

    // ── leg 2: execute the (deterministically rebuilt) batch, then revoke all deployer roles ──
    function _executeAndHandoff(DeployConfig.Cfg memory c, address deployer) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _wiringBatch(c);
        controller.executeBatch(targets, values, payloads, bytes32(0), c.salt);
        _handoffAndRenounce(c, deployer);
    }

    /// @dev Every call here is executed BY the controller (msg.sender == controller), the sole
    ///      holder of DEFAULT_ADMIN/TREASURY on the proxies. Stage-0 numbers from `DeployConfig`.
    function _wiringBatch(DeployConfig.Cfg memory c)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](16);
        values = new uint256[](16); // all zero (no ETH moved)
        payloads = new bytes[](16);

        address s = address(settlement);
        // settlement: operational role grants
        targets[0] = s;
        payloads[0] = abi.encodeCall(IAccessControl.grantRole, (Types.EXECUTOR_ROLE, c.executor));
        targets[1] = s;
        payloads[1] = abi.encodeCall(IAccessControl.grantRole, (Types.CREDIT_ADMIN_ROLE, c.creditAdmin));
        targets[2] = s;
        payloads[2] = abi.encodeCall(IAccessControl.grantRole, (Types.GUARDIAN_ROLE, c.guardian));
        // settlement: asset + first trusted signer
        targets[3] = s;
        payloads[3] = abi.encodeCall(SohoSettlement.setSupportedAsset, (c.usdc, true));
        targets[4] = s;
        payloads[4] = abi.encodeCall(SohoSettlement.setTrustedSigner, (c.firstTrustedSigner, true));
        // settlement: Stage-0 caps — tier-2 live; tier-0/1 dormant (ceilings 0)
        targets[5] = s;
        payloads[5] = abi.encodeCall(SohoSettlement.setTierCeilings, (2, c.tier2PerTx, c.tier2Daily));
        targets[6] = s;
        payloads[6] = abi.encodeCall(SohoSettlement.setTierCeilings, (0, 0, 0));
        targets[7] = s;
        payloads[7] = abi.encodeCall(SohoSettlement.setTierCeilings, (1, 0, 0));
        targets[8] = s;
        payloads[8] = abi.encodeCall(SohoSettlement.setGlobalDailyCap, (c.globalDailyCap));
        targets[9] = s;
        payloads[9] = abi.encodeCall(SohoSettlement.setGlobalOutstandingCap, (c.globalOutstandingCap));

        address v = address(vault);
        targets[10] = v;
        payloads[10] = abi.encodeCall(SohoVault.setSettlement, (s));
        targets[11] = v;
        payloads[11] = abi.encodeCall(SohoVault.setFirstLossReserve, (address(reserve)));
        targets[12] = v;
        payloads[12] = abi.encodeCall(SohoVault.setCooldown, (c.cooldown));
        targets[13] = v;
        payloads[13] = abi.encodeCall(SohoVault.setDepositCap, (c.vaultDepositCap));
        targets[14] = v;
        payloads[14] = abi.encodeCall(SohoVault.setInstantAllowance, (c.instantAllowance));

        targets[15] = address(reserve);
        payloads[15] = abi.encodeCall(SohoFirstLossReserve.setVault, (v));
    }

    // ── hand admin to the Treasury Safe, then revoke ALL deployer roles ──
    /// @dev OZ's TimelockController grants proposers PROPOSER+CANCELLER and executors EXECUTOR,
    ///      but DEFAULT_ADMIN only to the optional bootstrap `admin` (the deployer). The launch
    ///      checklist wants the Safe to be the controller admin, so grant it explicitly before
    ///      the deployer renounces — leaving the Safe with admin/proposer/executor/canceller and
    ///      the deployer with nothing anywhere.
    function _handoffAndRenounce(DeployConfig.Cfg memory c, address deployer) internal {
        controller.grantRole(controller.DEFAULT_ADMIN_ROLE(), c.treasurySafe);
        controller.renounceRole(controller.EXECUTOR_ROLE(), deployer);
        controller.renounceRole(controller.PROPOSER_ROLE(), deployer);
        controller.renounceRole(controller.DEFAULT_ADMIN_ROLE(), deployer); // admin last
    }

    function _log(address deployer, bytes32 phaseHash) internal view {
        console2.log("SohoTreasuryController:", address(controller));
        console2.log("SohoSettlement (proxy):", address(settlement));
        console2.log("  impl:", settlementImpl);
        console2.log("SohoVault (proxy):", address(vault));
        console2.log("  impl:", vaultImpl);
        console2.log("SohoFirstLossReserve (proxy):", address(reserve));
        console2.log("  impl:", reserveImpl);
        if (phaseHash == keccak256("schedule")) {
            // leg 1: roles are intentionally retained until the post-delay execute leg.
            console2.log("deployer (roles RETAINED until execute leg):", deployer);
        } else {
            console2.log("deployer (all roles renounced):", deployer);
        }
    }
}
