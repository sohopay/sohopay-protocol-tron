// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";

/// @title  DeployConfig
/// @notice Single source of deployment parameters for `Deploy` and `VerifyDeployment`.
///         ALL addresses come from the environment (no hardcoded production addresses);
///         numeric Stage-0 parameters default to the spec §7 / plan §10 Stage-0 table but
///         are overridable via env so the same script drives testnet / Phase-2 chains.
/// @dev    USDC is 6-decimal, so `$100 == 100e6`. Stage-0 (plan §10):
///         per-tx $100, global daily $1,000, global cumulative $5,000, anon-book $0,
///         vault cap $50k. Tier-0/1 ceilings = 0 (dormant). The anon-book ceiling ($0) is
///         the reserve balance (funded post-deploy), so it is not a constructor param here.
library DeployConfig {
    /// @dev forge-std cheatcode address (HEVM). Lets a library read env without `is Script`.
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Cfg {
        // ── external / role-holder addresses (REQUIRED from env; no defaults) ──
        address usdc; // settlement asset + vault asset + reserve asset (single USDC)
        address treasurySafe; // controller proposer/executor/canceller (3-of-5 cold)
        address feeRecipient; // protocol fee sink (settlement)
        address firstTrustedSigner; // first attestation signer (EIP-1271 capable)
        address executor; // EXECUTOR_ROLE on settlement (Turnkey settle bot)
        address creditAdmin; // CREDIT_ADMIN_ROLE on settlement
        address guardian; // GUARDIAN_ROLE on settlement (pause only)
        address warmRefill; // WARM_REFILL_ROLE on controller (optional; 0 to skip)
        // ── controller params ──
        uint256 minDelay; // 48h timelock for raises/params/signer/upgrade
        uint64 markDefaultDelay; // O2: < minDelay AND < vault cooldown
        uint96 hotFloatCeiling; // D-CUSTODY bound on settlement's reachable USDC
        // ── vault params ──
        uint64 cooldown; // O4: withdrawal cooldown; MUST exceed markDefaultDelay
        uint256 vaultDepositCap; // Stage-0 $50k
        uint96 instantAllowance; // O5 per-account-per-epoch (Stage-0 0 == queue-only)
        string vaultName;
        string vaultSymbol;
        // ── settlement Stage-0 caps ──
        uint96 tier2PerTx; // Stage-0 $100
        uint96 tier2Daily; // Stage-0 tier-2 daily ceiling (defaults to global daily)
        uint96 globalDailyCap; // Stage-0 $1,000
        uint96 globalOutstandingCap; // Stage-0 $5,000 (D5/I5 cumulative)
        // ── determinism / chain ──
        bytes32 salt; // CREATE2 base salt (Phase-2 address parity)
        uint256 expectedChainId; // EIP-712 domain chainId assertion (Base = 8453)
    }

    /// @notice Load config from env, applying Stage-0 defaults for numeric params.
    /// @dev Address fields use `envAddress` (revert if unset) — a launch must never silently
    ///      deploy with a zero/role address. `warmRefill` is optional (defaults to 0 = skip).
    function load() internal view returns (Cfg memory c) {
        c.usdc = vm.envAddress("USDC_ADDR");
        c.treasurySafe = vm.envAddress("TREASURY_SAFE");
        c.feeRecipient = vm.envAddress("FEE_RECIPIENT");
        c.firstTrustedSigner = vm.envAddress("FIRST_TRUSTED_SIGNER");
        c.executor = vm.envAddress("EXECUTOR_ADDR");
        c.creditAdmin = vm.envAddress("CREDIT_ADMIN_ADDR");
        c.guardian = vm.envAddress("GUARDIAN_ADDR");
        c.warmRefill = vm.envOr("WARM_REFILL_ADDR", address(0));

        c.minDelay = vm.envOr("MIN_DELAY", uint256(48 hours));
        c.markDefaultDelay = uint64(vm.envOr("MARK_DEFAULT_DELAY", uint256(24 hours)));
        c.hotFloatCeiling = uint96(vm.envOr("HOT_FLOAT_CEILING", uint256(2_000e6)));

        c.cooldown = uint64(vm.envOr("VAULT_COOLDOWN", uint256(48 hours)));
        c.vaultDepositCap = vm.envOr("VAULT_DEPOSIT_CAP", uint256(50_000e6));
        c.instantAllowance = uint96(vm.envOr("VAULT_INSTANT_ALLOWANCE", uint256(0)));
        c.vaultName = vm.envOr("VAULT_NAME", string("Soho USDC Vault"));
        c.vaultSymbol = vm.envOr("VAULT_SYMBOL", string("svUSDC"));

        c.tier2PerTx = uint96(vm.envOr("TIER2_PERTX", uint256(100e6)));
        c.globalDailyCap = uint96(vm.envOr("GLOBAL_DAILY_CAP", uint256(1_000e6)));
        // tier-2 daily defaults to the global daily cap (a single Stage-0 team agent may use
        // the whole daily envelope; still bounded by the independent global daily gate).
        c.tier2Daily = uint96(vm.envOr("TIER2_DAILY", uint256(c.globalDailyCap)));
        c.globalOutstandingCap = uint96(vm.envOr("GLOBAL_OUTSTANDING_CAP", uint256(5_000e6)));

        c.salt = vm.envOr("DEPLOY_SALT", keccak256("SOHOPAY_V1"));
        c.expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(8453));
    }

    /// @notice Per-contract CREATE2 salt derived from the base salt + a label, so all four
    ///         contracts get distinct deterministic addresses under one configured salt.
    function saltFor(bytes32 base, string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, label));
    }
}
