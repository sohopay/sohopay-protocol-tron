// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SohoSettlement} from "../src/SohoSettlement.sol";
import {SohoVault} from "../src/SohoVault.sol";
import {SohoFirstLossReserve} from "../src/SohoFirstLossReserve.sol";
import {Types} from "../src/libraries/Types.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

/// @title  DemoBaseA2A — "Pay Phil's agent $20" on Base Sepolia (chain 84532)
/// @notice Isolated experimental A2A demo. Registers Bob + Phil as agents, configures
///         Phil's receive address, and settles 20 USDC via `settleAgentToAgent`.
///         Phil is NOT registered as a merchant.
///
/// @dev    DEMO / EXPERIMENTAL. The A2A path is not covered by the prior v1 audit.
///         Isolated test deployment: deployer is the UUPS/treasury admin (no 48h
///         timelock) so one broadcast can deploy + settle on live Base Sepolia.
///         Never use this wiring for real funds.
///
/// Env: DEPLOYER_PRIVATE_KEY, BOB_AGENT_PRIVATE_KEY, TRUSTED_SIGNER_PRIVATE_KEY,
///      USDC_ADDR (optional; blank → MockUSDC), EXPECTED_CHAIN_ID (84532),
///      PHIL_RECEIVE_ADDRESS (optional; blank → deterministic demo address).
contract DemoBaseA2A is Script {
    using SafeERC20 for IERC20;

    bytes32 constant OWNER_ID = keccak256("A2A_OWNER");
    bytes32 constant BUSINESS_ID = keccak256("A2A_BUSINESS");
    bytes32 constant BOB_AGENT_ID = keccak256("BOB_AGENT");
    bytes32 constant PHIL_AGENT_ID = keccak256("PHIL_AGENT");

    /// @dev Official Circle USDC on Base Sepolia (developers.circle.com/stablecoins).
    address constant OFFICIAL_BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 constant LEND = 10_000e6;
    uint96 constant BOB_PER_TX = 25e6;
    uint96 constant BOB_DAILY = 50e6;
    uint256 constant PAY = 20e6;
    uint256 constant FEE = 0;
    uint256 constant BLOCKED = 30e6;

    SohoSettlement settlement;
    SohoVault vault;
    SohoFirstLossReserve reserve;
    IERC20 usdc;

    address deployer;
    address bobSigner;
    address philSigner;
    address trustedSigner;
    address philReceive;
    address bobReceive;
    uint256 trustedPk;
    uint256 bobPk;

    function run() external {
        // Local defaults are the well-known Anvil/Foundry throwaway keys.
        uint256 pk = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        deployer = vm.addr(pk);
        bobPk = vm.envOr(
            "BOB_AGENT_PRIVATE_KEY",
            uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)
        );
        bobSigner = vm.addr(bobPk);
        trustedPk = vm.envOr(
            "TRUSTED_SIGNER_PRIVATE_KEY",
            uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a)
        );
        trustedSigner = vm.addr(trustedPk);
        philSigner = vm.addr(vm.envOr("PHIL_AGENT_PRIVATE_KEY", uint256(keccak256("PHIL_AGENT_PK"))));
        philReceive = vm.envOr("PHIL_RECEIVE_ADDRESS", vm.addr(uint256(keccak256("PHIL_RECEIVE"))));
        bobReceive = vm.envOr("BOB_RECEIVE_ADDRESS", vm.addr(uint256(keccak256("BOB_RECEIVE"))));
        require(block.chainid == vm.envOr("EXPECTED_CHAIN_ID", uint256(84532)), "wrong chain");
        require(block.chainid != 9746, "Plasma chain is not the A2A Base demo");

        vm.startBroadcast(pk);
        _act1_deploy();
        _act2_register();
        _act3_receive();
        _act4_fund();
        _act5_to_9_payPhil20();
        // On a live broadcast, a reverting settle is a failed tx and forge aborts
        // before later receipts are useful. Keep the cap check for local runs.
        if (!vm.envOr("SKIP_A2A_BLOCKED_ACT", false)) {
            _act10_blocked();
        }
        vm.stopBroadcast();
    }

    function _act1_deploy() internal {
        address assetAddr = vm.envOr("USDC_ADDR", address(0));
        if (assetAddr == address(0)) {
            assetAddr = address(new MockUSDC());
            console2.log("MockUSDC:", assetAddr);
        } else if (assetAddr == OFFICIAL_BASE_SEPOLIA_USDC) {
            console2.log("Official Base Sepolia USDC:", assetAddr);
        }
        usdc = IERC20(assetAddr);

        reserve = SohoFirstLossReserve(
            address(
                new ERC1967Proxy(
                    address(new SohoFirstLossReserve()),
                    abi.encodeCall(SohoFirstLossReserve.initialize, (usdc, deployer))
                )
            )
        );
        vault = SohoVault(
            address(
                new ERC1967Proxy(
                    address(new SohoVault()),
                    abi.encodeCall(SohoVault.initialize, (usdc, "Soho A2A USDC Vault", "svUSDC", deployer))
                )
            )
        );
        settlement = SohoSettlement(
            address(
                new ERC1967Proxy(
                    address(new SohoSettlement()),
                    abi.encodeCall(
                        SohoSettlement.initialize, (deployer, address(usdc), address(vault), deployer)
                    )
                )
            )
        );

        settlement.grantRole(Types.EXECUTOR_ROLE, deployer);
        settlement.grantRole(Types.CREDIT_ADMIN_ROLE, deployer);
        settlement.grantRole(Types.GUARDIAN_ROLE, deployer);
        settlement.setSupportedAsset(address(usdc), true);
        settlement.setTrustedSigner(trustedSigner, true);
        settlement.setTierCeilings(2, 100e6, 1_000e6);
        settlement.setGlobalDailyCap(1_000e6);
        settlement.setGlobalOutstandingCap(5_000e6);

        vault.setSettlement(address(settlement));
        vault.setFirstLossReserve(address(reserve));
        vault.setDepositCap(50_000e6);
        reserve.setVault(address(vault));
    }

    function _act2_register() internal {
        settlement.registerOwner(OWNER_ID);
        settlement.registerBusiness(BUSINESS_ID, OWNER_ID);
        settlement.registerAgent(
            BOB_AGENT_ID,
            BUSINESS_ID,
            bobSigner,
            2,
            BOB_PER_TX,
            BOB_DAILY,
            uint64(block.timestamp + 365 days),
            keccak256("BOB_MANDATE")
        );
        settlement.registerAgent(
            PHIL_AGENT_ID,
            BUSINESS_ID,
            philSigner,
            2,
            BOB_PER_TX,
            BOB_DAILY,
            uint64(block.timestamp + 365 days),
            keccak256("PHIL_MANDATE")
        );
        require(settlement.getAgent(BOB_AGENT_ID).status == Types.Status.Active, "Bob not Active");
        require(settlement.getAgent(PHIL_AGENT_ID).status == Types.Status.Active, "Phil not Active");
        require(
            settlement.getMerchant(PHIL_AGENT_ID).status == Types.Status.None, "Phil must not be a merchant"
        );
    }

    function _act3_receive() internal {
        require(philReceive != address(0), "Phil receive unset");
        settlement.setAgentReceive(BOB_AGENT_ID, bobReceive);
        settlement.setAgentReceive(PHIL_AGENT_ID, philReceive);
        require(settlement.agentReceive(PHIL_AGENT_ID) == philReceive, "Phil receive not set");
        require(settlement.agentReceive(PHIL_AGENT_ID) != philSigner, "must not use Phil signer");
    }

    function _act4_fund() internal {
        _fund(address(settlement), 1_000e6);
        _fund(deployer, LEND);
        usdc.forceApprove(address(vault), LEND);
        vault.deposit(LEND, deployer);
    }

    function _act5_to_9_payPhil20() internal {
        console2.log("====================================================");
        console2.log(unicode"SOHOPAY — AGENT TO AGENT PAYMENT DEMO");
        console2.log("====================================================");
        console2.log("");
        console2.log("Network:");
        console2.log("Base Sepolia");
        console2.log("");
        console2.log("Command:");
        console2.log("\"Pay Phil's agent $20\"");
        console2.log("");
        console2.log("Payer:");
        console2.log("Bob Agent");
        console2.logBytes32(BOB_AGENT_ID);
        console2.log(bobSigner);
        console2.log("");
        console2.log("Payee:");
        console2.log("Phil Agent");
        console2.logBytes32(PHIL_AGENT_ID);
        console2.log(philReceive);
        console2.log("");
        console2.log("Payee registered:");
        console2.log("YES");
        console2.log("");
        console2.log("Payee merchant:");
        console2.log("NO");
        console2.log("");
        console2.log("Amount:");
        console2.log("20 USDC");
        console2.log("");

        require(settlement.getAgent(BOB_AGENT_ID).status == Types.Status.Active, "Bob inactive");
        console2.log("Checking Bob Agent...");
        console2.log("PASS");
        console2.log("");

        require(settlement.getAgent(PHIL_AGENT_ID).status == Types.Status.Active, "Phil inactive");
        require(settlement.getMerchant(PHIL_AGENT_ID).status == Types.Status.None, "Phil is a merchant");
        console2.log("Checking Phil Agent...");
        console2.log("PASS");
        console2.log("");

        require(PAY <= BOB_PER_TX, "above per-tx");
        console2.log("Checking spending limits...");
        console2.log("PASS");
        console2.log("");

        Types.AgentPaymentIntent memory intent = Types.AgentPaymentIntent({
            payerAgentId: BOB_AGENT_ID,
            payeeAgentId: PHIL_AGENT_ID,
            asset: address(usdc),
            amount: PAY,
            feeAmount: FEE,
            orderRef: keccak256("PAY-PHIL-20"),
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });
        bytes32 paymentId = settlement.computeAgentPaymentId(intent);
        console2.log("Creating A2A PaymentIntent...");
        console2.log("PASS");
        console2.log("");

        Types.CreditAttestation memory att = Types.CreditAttestation({
            paymentId: paymentId,
            agentId: BOB_AGENT_ID,
            asset: address(usdc),
            amount: PAY,
            feeAmount: FEE,
            deadline: block.timestamp + 1 hours
        });

        bytes memory intentSig = _sign(bobPk, settlement.agentIntentDigest(intent));
        bytes memory attSig = _sign(trustedPk, settlement.attestationDigest(att));
        console2.log("Verifying agent signature...");
        console2.log("PASS");
        console2.log("");
        console2.log("Verifying trusted credit attestation...");
        console2.log("PASS");
        console2.log("");

        (,,, uint256 cid, address vc,,) = settlement.eip712Domain();
        require(cid == block.chainid && vc == address(settlement), "EIP-712 domain mismatch");

        uint256 philBefore = usdc.balanceOf(philReceive);
        console2.log("Phil balance before:");
        console2.log(philBefore);

        console2.log("Executing payment...");
        settlement.settleAgentToAgent(intent, intentSig, att, attSig, trustedSigner);
        console2.log("PASS");
        console2.log("");

        uint256 philAfter = usdc.balanceOf(philReceive);
        uint256 received = philAfter - philBefore;
        require(received == 20_000_000, "Phil did not receive 20 USDC");
        require(settlement.isSettled(paymentId), "payment not marked used");
        require(settlement.getAgent(BOB_AGENT_ID).outstandingDebt == uint96(PAY + FEE), "debt mismatch");
        require(settlement.getMerchant(PHIL_AGENT_ID).status == Types.Status.None, "Phil became a merchant");

        console2.log("Phil balance after:");
        console2.log(philAfter);
        console2.log("");
        console2.log("Received:");
        console2.log("20 USDC");
        console2.log("");
        console2.log("Bob outstanding debt:");
        console2.log(uint256(settlement.getAgent(BOB_AGENT_ID).outstandingDebt));
        console2.log("");
        console2.log("Settlement:");
        console2.log(address(settlement));
        console2.log("");
        console2.log("====================================================");
        console2.log("A2A PAYMENT COMPLETE");
        console2.log("====================================================");
    }

    function _act10_blocked() internal {
        Types.AgentPaymentIntent memory intent = Types.AgentPaymentIntent({
            payerAgentId: BOB_AGENT_ID,
            payeeAgentId: PHIL_AGENT_ID,
            asset: address(usdc),
            amount: BLOCKED,
            feeAmount: FEE,
            orderRef: keccak256("PAY-PHIL-30-BLOCKED"),
            nonce: 2,
            deadline: block.timestamp + 1 hours
        });
        Types.CreditAttestation memory att = Types.CreditAttestation({
            paymentId: settlement.computeAgentPaymentId(intent),
            agentId: BOB_AGENT_ID,
            asset: address(usdc),
            amount: BLOCKED,
            feeAmount: FEE,
            deadline: block.timestamp + 1 hours
        });
        bytes memory intentSig = _sign(bobPk, settlement.agentIntentDigest(intent));
        bytes memory attSig = _sign(trustedPk, settlement.attestationDigest(att));
        try settlement.settleAgentToAgent(intent, intentSig, att, attSig, trustedSigner) {
            revert("30 USDC should exceed Bob per-tx cap");
        } catch {
            console2.log("");
            console2.log("Blocked payment (30 USDC > 25 USDC per-tx): REVERT");
        }
    }

    function _fund(address to, uint256 amount) internal {
        try MockUSDC(address(usdc)).mint(to, amount) {} catch {}
    }

    function _sign(uint256 sk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(sk, digest);
        return abi.encodePacked(r, ss, vv);
    }
}
