// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SohoTreasuryController} from "../src/SohoTreasuryController.sol";
import {SohoSettlement} from "../src/SohoSettlement.sol";
import {SohoVault} from "../src/SohoVault.sol";
import {SohoFirstLossReserve} from "../src/SohoFirstLossReserve.sol";
import {Types} from "../src/libraries/Types.sol";
import {DeployConfig} from "./DeployConfig.sol";

/// @title  VerifyDeployment
/// @notice Post-deploy assertion script — the machine-checkable launch-checklist items
///         (plan §11, spec §7). Reverts on the first failed invariant; prints a pass line.
///         Reads deployed addresses from env (*_ADDR / *_IMPL) and expected params from
///         `DeployConfig`. Run AFTER `Deploy` has fully settled (including the timelock
///         execute + deployer renounce legs).
///
/// @dev    Cap fields (`_tierCeilings`, `_globalDailyCap`, `_globalOutstandingCap`) have no
///         public getters, so they are read from raw storage via `vm.load`. Slots are taken
///         from `forge inspect src/SohoSettlement.sol:SohoSettlement storage-layout`:
///         `_tierCeilings` mapping base = slot 0; `_globalDailyCap` = slot 1 (offset 0,
///         uint96); `_globalOutstandingCap` = slot 2 (offset 12, uint96). The packed
///         TierCeiling{uint96 perTx; uint96 daily;} sits in one value word (perTx low,
///         daily high). If the layout changes this script must be regenerated from inspect.
contract VerifyDeployment is Script {
    bytes32 internal constant TIER_CEILINGS_SLOT = bytes32(uint256(0));
    bytes32 internal constant GLOBAL_DAILY_SLOT = bytes32(uint256(1));
    bytes32 internal constant GLOBAL_OUTSTANDING_SLOT = bytes32(uint256(2));
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1.
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    SohoTreasuryController internal controller;
    SohoSettlement internal settlement;
    SohoVault internal vault;
    SohoFirstLossReserve internal reserve;
    address internal deployer;

    function run() external {
        DeployConfig.Cfg memory c = DeployConfig.load();
        controller = SohoTreasuryController(payable(vm.envAddress("CONTROLLER_ADDR")));
        settlement = SohoSettlement(vm.envAddress("SETTLEMENT_ADDR"));
        vault = SohoVault(vm.envAddress("VAULT_ADDR"));
        reserve = SohoFirstLossReserve(vm.envAddress("RESERVE_ADDR"));
        deployer = vm.envAddress("DEPLOYER_ADDR");

        _checkAdminIsController(c);
        _checkDeployerHasNoRoles();
        _checkNoGuardianSignerOverlap(c);
        _checkOperationalGrants(c);
        _checkDomain(c);
        _checkStageZeroCaps(c);
        _checkTiersDormant();
        _checkCooldownExceedsMarkDefault();
        _checkProxyImpls();
        _checkWiringConsistency();

        console2.log("VerifyDeployment: ALL CHECKS PASSED");
    }

    // 1. DEFAULT_ADMIN on every contract == controller; controller admin == Treasury Safe.
    function _checkAdminIsController(DeployConfig.Cfg memory c) internal view {
        bytes32 admin = 0x00; // DEFAULT_ADMIN_ROLE
        require(settlement.hasRole(admin, address(controller)), "settlement admin != controller");
        require(vault.hasRole(admin, address(controller)), "vault admin != controller");
        require(reserve.hasRole(admin, address(controller)), "reserve admin != controller");
        // upgrade authority (D14) is the controller on all three proxies.
        require(settlement.treasuryController() == address(controller), "settlement upgradeAuth");
        require(vault.treasuryController() == address(controller), "vault upgradeAuth");
        require(reserve.treasuryController() == address(controller), "reserve upgradeAuth");
        // controller itself is administered by the Treasury Safe (and self).
        require(controller.hasRole(admin, c.treasurySafe), "controller admin != safe");
        require(controller.hasRole(controller.PROPOSER_ROLE(), c.treasurySafe), "safe !proposer");
        require(controller.hasRole(controller.EXECUTOR_ROLE(), c.treasurySafe), "safe !executor");
    }

    // 2. Deployer holds ZERO roles anywhere (proxies + controller).
    function _checkDeployerHasNoRoles() internal view {
        bytes32 admin = 0x00;
        require(!settlement.hasRole(admin, deployer), "deployer admin@settlement");
        require(!settlement.hasRole(Types.TREASURY_ROLE, deployer), "deployer treasury@settlement");
        require(!settlement.hasRole(Types.EXECUTOR_ROLE, deployer), "deployer executor@settlement");
        require(!settlement.hasRole(Types.CREDIT_ADMIN_ROLE, deployer), "deployer credit@settlement");
        require(!settlement.hasRole(Types.GUARDIAN_ROLE, deployer), "deployer guardian@settlement");
        require(!vault.hasRole(admin, deployer), "deployer admin@vault");
        require(!vault.hasRole(Types.TREASURY_ROLE, deployer), "deployer treasury@vault");
        require(!reserve.hasRole(admin, deployer), "deployer admin@reserve");
        require(!reserve.hasRole(Types.TREASURY_ROLE, deployer), "deployer treasury@reserve");
        require(!controller.hasRole(admin, deployer), "deployer admin@controller");
        require(!controller.hasRole(controller.PROPOSER_ROLE(), deployer), "deployer proposer@controller");
        require(!controller.hasRole(controller.EXECUTOR_ROLE(), deployer), "deployer executor@controller");
        require(!controller.hasRole(controller.CANCELLER_ROLE(), deployer), "deployer canceller@controller");
        require(!controller.hasRole(controller.WARM_REFILL_ROLE(), deployer), "deployer warm@controller");
    }

    // 3. INV-8: no address holds GUARDIAN_ROLE and is a trusted signer.
    function _checkNoGuardianSignerOverlap(DeployConfig.Cfg memory c) internal view {
        require(c.firstTrustedSigner != c.guardian, "INV-8 config: signer==guardian");
        require(!settlement.trustedSigners(c.guardian), "INV-8: guardian is trusted signer");
        require(!settlement.hasRole(Types.GUARDIAN_ROLE, c.firstTrustedSigner), "INV-8: signer is guardian");
    }

    // 4. EXECUTOR + CREDIT_ADMIN + GUARDIAN granted to expected addrs; signer set non-empty.
    function _checkOperationalGrants(DeployConfig.Cfg memory c) internal view {
        require(settlement.hasRole(Types.EXECUTOR_ROLE, c.executor), "executor not granted");
        require(settlement.hasRole(Types.CREDIT_ADMIN_ROLE, c.creditAdmin), "creditAdmin not granted");
        require(settlement.hasRole(Types.GUARDIAN_ROLE, c.guardian), "guardian not granted");
        require(settlement.trustedSigners(c.firstTrustedSigner), "first trusted signer unset");
        if (c.warmRefill != address(0)) {
            require(controller.hasRole(controller.WARM_REFILL_ROLE(), c.warmRefill), "warmRefill not granted");
        }
    }

    // 5. EIP-712 domain == ("SohoSettlement","1",<chainId>,<settlement>).
    function _checkDomain(DeployConfig.Cfg memory c) internal view {
        (, string memory name, string memory version, uint256 chainId, address verifying,,) =
            settlement.eip712Domain();
        require(keccak256(bytes(name)) == keccak256("SohoSettlement"), "domain name");
        require(keccak256(bytes(version)) == keccak256("1"), "domain version");
        require(chainId == c.expectedChainId, "domain chainId");
        require(verifying == address(settlement), "domain verifyingContract");
    }

    // 6. Stage-0 caps + asset + fee + deposit cap.
    function _checkStageZeroCaps(DeployConfig.Cfg memory c) internal view {
        (uint96 perTx2, uint96 daily2) = _tierCeiling(2);
        require(perTx2 == c.tier2PerTx, "tier2 perTx");
        require(daily2 == c.tier2Daily, "tier2 daily");
        require(
            uint96(uint256(vm.load(address(settlement), GLOBAL_DAILY_SLOT))) == c.globalDailyCap,
            "globalDaily"
        );
        require(
            uint96(uint256(vm.load(address(settlement), GLOBAL_OUTSTANDING_SLOT)) >> 96)
                == c.globalOutstandingCap,
            "globalOutstanding"
        );
        require(settlement.isSupportedAsset(c.usdc), "usdc unsupported");
        require(settlement.feeRecipient() == c.feeRecipient, "feeRecipient");
        require(vault.depositCap() == c.vaultDepositCap, "vault depositCap");
    }

    // 7. Tier-0/1 dormant (ceilings == 0).
    function _checkTiersDormant() internal view {
        (uint96 p0, uint96 d0) = _tierCeiling(0);
        (uint96 p1, uint96 d1) = _tierCeiling(1);
        require(p0 == 0 && d0 == 0, "tier0 not dormant");
        require(p1 == 0 && d1 == 0, "tier1 not dormant");
    }

    // 8. Vault cooldown strictly exceeds the controller's markDefault delay (O2/O4).
    function _checkCooldownExceedsMarkDefault() internal view {
        require(vault.cooldown() > controller.markDefaultDelay(), "cooldown<=markDefaultDelay");
    }

    // 9. Each proxy points at its expected implementation.
    function _checkProxyImpls() internal view {
        require(_impl(address(settlement)) == vm.envAddress("SETTLEMENT_IMPL"), "settlement impl");
        require(_impl(address(vault)) == vm.envAddress("VAULT_IMPL"), "vault impl");
        require(_impl(address(reserve)) == vm.envAddress("RESERVE_IMPL"), "reserve impl");
    }

    // 10. settlement <-> vault <-> reserve <-> controller cross-references are consistent.
    function _checkWiringConsistency() internal view {
        require(settlement.vault() == address(vault), "settlement.vault");
        require(vault.settlement() == address(settlement), "vault.settlement");
        require(vault.firstLossReserve() == address(reserve), "vault.reserve");
        require(reserve.vault() == address(vault), "reserve.vault");
        require(controller.settlement() == address(settlement), "controller.settlement");
    }

    // ── storage helpers ──
    function _tierCeiling(uint8 tier) internal view returns (uint96 perTx, uint96 daily) {
        bytes32 slot = keccak256(abi.encode(uint256(tier), uint256(TIER_CEILINGS_SLOT)));
        uint256 word = uint256(vm.load(address(settlement), slot));
        perTx = uint96(word);
        daily = uint96(word >> 96);
    }

    function _impl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }
}
