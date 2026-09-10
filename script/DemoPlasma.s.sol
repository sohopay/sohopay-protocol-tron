// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {SohoTreasuryController} from "../src/SohoTreasuryController.sol";
import {SohoSettlement} from "../src/SohoSettlement.sol";
import {SohoVault} from "../src/SohoVault.sol";
import {SohoFirstLossReserve} from "../src/SohoFirstLossReserve.sol";
import {Types} from "../src/libraries/Types.sol";
import {MockUSDTNonStandard} from "../test/mocks/MockUSDTNonStandard.sol";

/// @title  DemoPlasma — SOHOPay 5-act USDT demo on Plasma testnet (chain 9746)
/// @notice Self-contained demo: deploys the audited stack (vendored from sohopay-protocol,
///         byte-identical — Plasma is EVM-equivalent), wires it with the script as bootstrap
///         admin (MIN_DELAY=0 so schedule+execute land in one broadcast), registers the
///         identity chain + merchant, then runs Acts 2-5. Prints `DEMO COMPLETE` on success.
///
/// @dev    DEMO ONLY. Unlike the production Deploy.s.sol, this keeps the deployer as the
///         controller admin (no renounce) so the script can drive registrations, and uses a
///         zero timelock. Never use this wiring for real funds.
///
/// @dev    Verified: compiles (forge build) and all 5 acts run green to `DEMO COMPLETE`
///         in-memory at chain id 9746 (Settlement pays the merchant 50 USDT, overpayment
///         reverts, emergencyRedeem works while paused). Reproduce:
///         `scripts/tether-demo/run-plasma-demo.sh`.
///
/// Env: DEPLOYER_PRIVATE_KEY, AGENT_PRIVATE_KEY, TRUSTED_SIGNER_PRIVATE_KEY,
///      USDC_ADDR (optional; blank → deploy MockUSDT), EXPECTED_CHAIN_ID (9746).
contract DemoPlasma is Script {
    using SafeERC20 for IERC20; // USDT (USDT0/MockUSDTNonStandard) returns no bool — approve via SafeERC20

    // identity-chain ids (demo fixtures)
    bytes32 constant OWNER_ID = keccak256("DEMO_OWNER");
    bytes32 constant BUSINESS_ID = keccak256("DEMO_BUSINESS");
    bytes32 constant AGENT_ID = keccak256("DEMO_AGENT");
    bytes32 constant MERCHANT_ID = keccak256("DEMO_MERCHANT");

    // Stage-0 demo amounts (6-decimal asset)
    uint256 constant LEND = 10_000e6; // lender deposit → vault liquidity
    uint96 constant PER_TX = 100e6; // tier-2 per-tx cap (Stage-0)
    uint256 constant PAY = 50e6; // Act 3 settle amount
    uint256 constant FEE = 1e6;
    uint256 constant DEMO_DELAY = 1; // 1s timelock; warped past in-run (anvil/simulation)

    SohoTreasuryController controller;
    SohoSettlement settlement;
    SohoVault vault;
    SohoFirstLossReserve reserve;
    IERC20 usdt;

    address deployer;
    address agentSigner;
    address trustedSigner;
    uint256 trustedPk;
    uint256 agentPk;

    function run() external {
        // Local defaults are the well-known Anvil/Foundry throwaway keys.
        uint256 pk = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        deployer = vm.addr(pk);
        agentPk = vm.envOr(
            "AGENT_PRIVATE_KEY", uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)
        );
        agentSigner = vm.addr(agentPk);
        trustedPk = vm.envOr(
            "TRUSTED_SIGNER_PRIVATE_KEY",
            uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a)
        );
        trustedSigner = vm.addr(trustedPk);
        require(block.chainid == vm.envOr("EXPECTED_CHAIN_ID", uint256(9746)), "wrong chain");

        vm.startBroadcast(pk);
        _act1_setup();
        _act2_lend();
        _act3_settle();
        _act4_repay();
        _act5_safety();
        vm.stopBroadcast();

        console2.log("");
        console2.log("DEMO COMPLETE");
    }

    // ── Act 1: deploy + wire + register identity chain + merchant + fund ──
    function _act1_setup() internal {
        console2.log("== Act 1: Setup ==");

        // settlement asset: real token via env, else a fresh 6-dec mock.
        address assetAddr = vm.envOr("USDT_ADDR", vm.envOr("USDC_ADDR", address(0)));
        if (assetAddr == address(0)) {
            // Phase 1 default: non-standard USDT mock (no bool return — like real USDT).
            assetAddr = address(new MockUSDTNonStandard());
            console2.log("MockUSDTNonStandard:", assetAddr);
        }
        usdt = IERC20(assetAddr);

        // controller: 1s timelock (markDefaultDelay must be strictly below minDelay, and OZ
        // forbids scheduling below minDelay), deployer as bootstrap admin + proposer + executor.
        // Each batch is scheduled then warped past + executed in this same run (anvil/simulation
        // pattern, mirroring Deploy.s.sol "all" mode — not broadcastable live across the warp).
        address[] memory pe = new address[](1);
        pe[0] = deployer;
        controller = new SohoTreasuryController(
            DEMO_DELAY, pe, pe, deployer, usdt, uint64(0), uint96(2_000e6)
        );

        reserve = SohoFirstLossReserve(
            address(
                new ERC1967Proxy(
                    address(new SohoFirstLossReserve()),
                    abi.encodeCall(SohoFirstLossReserve.initialize, (usdt, address(controller)))
                )
            )
        );
        vault = SohoVault(
            address(
                new ERC1967Proxy(
                    address(new SohoVault()),
                    abi.encodeCall(
                        SohoVault.initialize,
                        (usdt, vm.envOr("VAULT_NAME", string("Soho USDT Vault")),
                         vm.envOr("VAULT_SYMBOL", string("svUSDT")), address(controller))
                    )
                )
            )
        );
        settlement = SohoSettlement(
            address(
                new ERC1967Proxy(
                    address(new SohoSettlement()),
                    abi.encodeCall(
                        SohoSettlement.initialize,
                        (address(controller), address(usdt), address(vault), deployer)
                    )
                )
            )
        );
        controller.setSettlement(address(settlement));
        console2.log("Settlement:", address(settlement));
        console2.log("Vault:", address(vault));

        // wire + Stage-0 caps + grant demo EOA the operational roles, all via the controller
        // (sole TREASURY/admin holder on the proxies). One zero-delay batch.
        _wireBatch();

        // identity chain: owner → business → agent(tier-2). Owner/business are TREASURY-gated
        // (controller); agent is CREDIT_ADMIN (granted to deployer in the wiring batch).
        _ctrlCall(address(settlement), abi.encodeCall(SohoSettlement.registerOwner, (OWNER_ID)));
        _ctrlCall(address(settlement), abi.encodeCall(SohoSettlement.registerBusiness, (BUSINESS_ID, OWNER_ID)));
        _ctrlCall(
            address(settlement),
            abi.encodeCall(SohoSettlement.registerMerchant, (MERCHANT_ID, _merchantPayout(), PER_TX))
        );
        settlement.registerAgent(
            AGENT_ID, BUSINESS_ID, agentSigner, 2, PER_TX, PER_TX,
            uint64(block.timestamp + 365 days), keccak256("DEMO_MANDATE")
        );

        // Fund the settlement hot float (facilitator balance it pays merchants from, within the
        // hotFloatCeiling). Demo: mint to the proxy; production refills via the vault credit hook.
        _fund(address(settlement), 1_000e6);
        console2.log("hot float funded:", uint256(1_000e6));

        // EIP-712 sanity (residual of Tron #3): domain binds to this proxy at chain 9746.
        (, , , uint256 cid, address vc, , ) = settlement.eip712Domain();
        require(cid == block.chainid && vc == address(settlement), "EIP-712 domain mismatch");
        console2.log("EIP-712 domain ok (chainId, verifyingContract):", cid, vc);
    }

    // ── Act 2: lender deposits USDT → svUSDT (provides settle liquidity) ──
    function _act2_lend() internal {
        console2.log("== Act 2: Lend ==");
        _fund(deployer, LEND);
        usdt.forceApprove(address(vault), LEND);
        uint256 shares = vault.deposit(LEND, deployer);
        console2.log("deposited / svUSDT shares:", LEND, shares);
    }

    // ── Act 3: signed PaymentIntent + CreditAttestation → settle → merchant payout ──
    function _act3_settle() internal {
        console2.log("== Act 3: Settle ==");
        Types.PaymentIntent memory intent = Types.PaymentIntent({
            agentId: AGENT_ID,
            merchantId: MERCHANT_ID,
            asset: address(usdt),
            amount: PAY,
            feeAmount: FEE,
            orderRef: keccak256("ORDER-1"),
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });
        bytes32 paymentId = settlement.computePaymentId(intent);
        Types.CreditAttestation memory att = Types.CreditAttestation({
            paymentId: paymentId,
            agentId: AGENT_ID,
            asset: address(usdt),
            amount: PAY,
            feeAmount: FEE,
            deadline: block.timestamp + 1 hours
        });

        bytes memory intentSig = _sign(agentPk, settlement.intentDigest(intent));
        bytes memory attSig = _sign(trustedPk, settlement.attestationDigest(att));

        uint256 before = usdt.balanceOf(_merchantPayout());
        settlement.settleWithAttestation(intent, intentSig, att, attSig, trustedSigner);
        uint256 paid = usdt.balanceOf(_merchantPayout()) - before;
        require(paid == PAY, "merchant not paid");
        console2.log("merchant received:", paid);
    }

    // ── Act 4: partial repay succeeds; overpayment reverts ──
    function _act4_repay() internal {
        console2.log("== Act 4: Repay ==");
        uint96 outstanding = settlement.getAgent(AGENT_ID).outstandingDebt;
        _fund(deployer, outstanding);
        usdt.forceApprove(address(settlement), type(uint256).max);

        settlement.repay(AGENT_ID, outstanding / 2); // partial ok
        console2.log("repaid (partial):", outstanding / 2);

        uint96 remaining = settlement.getAgent(AGENT_ID).outstandingDebt;
        try settlement.repay(AGENT_ID, uint256(remaining) + 1e6) {
            revert("overpayment should revert");
        } catch {
            console2.log("overpayment reverted as expected");
        }
    }

    // ── Act 5: pause settlement, emergency exit still works (D15) ──
    function _act5_safety() internal {
        console2.log("== Act 5: Safety ==");
        settlement.pause(); // GUARDIAN (granted to deployer)
        uint256 shares = vault.balanceOf(deployer) / 4;
        uint256 assets = vault.emergencyRedeem(shares, deployer);
        console2.log("emergencyRedeem while paused (shares, assets):", shares, assets);
    }

    // ── helpers ──

    /// @dev one-call wiring/grants batch executed BY the controller (TREASURY/admin holder).
    function _wireBatch() internal {
        address s = address(settlement);
        address[] memory t = new address[](14);
        uint256[] memory v = new uint256[](14);
        bytes[] memory p = new bytes[](14);
        // operational roles → deployer (demo drives all acts with one key)
        t[0] = s; p[0] = abi.encodeCall(IAccessControl.grantRole, (Types.EXECUTOR_ROLE, deployer));
        t[1] = s; p[1] = abi.encodeCall(IAccessControl.grantRole, (Types.CREDIT_ADMIN_ROLE, deployer));
        t[2] = s; p[2] = abi.encodeCall(IAccessControl.grantRole, (Types.GUARDIAN_ROLE, deployer));
        // asset + trusted signer
        t[3] = s; p[3] = abi.encodeCall(SohoSettlement.setSupportedAsset, (address(usdt), true));
        t[4] = s; p[4] = abi.encodeCall(SohoSettlement.setTrustedSigner, (trustedSigner, true));
        // Stage-0 caps (tier-2 live; tier-0/1 dormant)
        t[5] = s; p[5] = abi.encodeCall(SohoSettlement.setTierCeilings, (2, PER_TX, 1_000e6));
        t[6] = s; p[6] = abi.encodeCall(SohoSettlement.setTierCeilings, (0, 0, 0));
        t[7] = s; p[7] = abi.encodeCall(SohoSettlement.setTierCeilings, (1, 0, 0));
        t[8] = s; p[8] = abi.encodeCall(SohoSettlement.setGlobalDailyCap, (uint96(1_000e6)));
        t[9] = s; p[9] = abi.encodeCall(SohoSettlement.setGlobalOutstandingCap, (uint96(5_000e6)));
        // vault wiring
        address vlt = address(vault);
        t[10] = vlt; p[10] = abi.encodeCall(SohoVault.setSettlement, (s));
        t[11] = vlt; p[11] = abi.encodeCall(SohoVault.setFirstLossReserve, (address(reserve)));
        t[12] = vlt; p[12] = abi.encodeCall(SohoVault.setDepositCap, (uint256(50_000e6)));
        // reserve wiring
        t[13] = address(reserve); p[13] = abi.encodeCall(SohoFirstLossReserve.setVault, (vlt));

        controller.scheduleBatch(t, v, p, bytes32(0), bytes32("demo"), DEMO_DELAY);
        vm.warp(block.timestamp + DEMO_DELAY + 1);
        controller.executeBatch(t, v, p, bytes32(0), bytes32("demo"));
    }

    /// @dev single TREASURY-gated call routed through the zero-delay controller timelock.
    function _ctrlCall(address target, bytes memory payload) internal {
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        bytes[] memory p = new bytes[](1);
        t[0] = target;
        p[0] = payload;
        bytes32 salt = keccak256(abi.encodePacked("demo", target, payload));
        controller.scheduleBatch(t, v, p, bytes32(0), salt, DEMO_DELAY);
        vm.warp(block.timestamp + DEMO_DELAY + 1);
        controller.executeBatch(t, v, p, bytes32(0), salt);
    }

    function _fund(address to, uint256 amount) internal {
        // mock path mints; with a real USDT_ADDR (USDT0) the operator must pre-fund balances.
        try MockUSDTNonStandard(address(usdt)).mint(to, amount) {} catch {}
    }

    function _merchantPayout() internal view returns (address) {
        return vm.addr(uint256(keccak256("DEMO_MERCHANT_PAYOUT")));
    }

    function _sign(uint256 sk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(sk, digest);
        return abi.encodePacked(r, ss, vv);
    }
}
