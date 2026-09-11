// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SohoSettlement} from "../src/SohoSettlement.sol";
import {Types} from "../src/libraries/Types.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

/// @notice One on-chain A2A settle against an existing Base Sepolia deployment.
///         Experimental — not covered by the prior v1 audit.
contract SettleBaseA2A is Script {
    bytes32 constant BOB_AGENT_ID = keccak256("BOB_AGENT");
    bytes32 constant PHIL_AGENT_ID = keccak256("PHIL_AGENT");

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 bobPk = vm.envUint("BOB_AGENT_PRIVATE_KEY");
        uint256 trustedPk = vm.envUint("TRUSTED_SIGNER_PRIVATE_KEY");
        address trustedSigner = vm.addr(trustedPk);
        SohoSettlement settlement = SohoSettlement(vm.envAddress("SETTLEMENT_ADDR"));
        IERC20 usdc = IERC20(vm.envAddress("USDC_ADDR"));
        uint256 amount = vm.envUint("A2A_AMOUNT");
        uint256 nonce = vm.envUint("A2A_NONCE");
        require(block.chainid == 84532, "wrong chain");
        require(amount > 0, "amount");

        Types.AgentPaymentIntent memory intent = Types.AgentPaymentIntent({
            payerAgentId: BOB_AGENT_ID,
            payeeAgentId: PHIL_AGENT_ID,
            asset: address(usdc),
            amount: amount,
            feeAmount: 0,
            orderRef: keccak256(abi.encodePacked("SOHOPAY-A2A", nonce)),
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
        bytes32 paymentId = settlement.computeAgentPaymentId(intent);
        Types.CreditAttestation memory att = Types.CreditAttestation({
            paymentId: paymentId,
            agentId: BOB_AGENT_ID,
            asset: address(usdc),
            amount: amount,
            feeAmount: 0,
            deadline: block.timestamp + 1 hours
        });

        address philReceive = settlement.agentReceive(PHIL_AGENT_ID);
        uint256 beforeBal = usdc.balanceOf(philReceive);

        vm.startBroadcast(pk);
        _ensureCapacity(settlement, usdc, amount);
        settlement.settleAgentToAgent(
            intent,
            _sign(bobPk, settlement.agentIntentDigest(intent)),
            att,
            _sign(trustedPk, settlement.attestationDigest(att)),
            trustedSigner
        );
        vm.stopBroadcast();

        uint256 received = usdc.balanceOf(philReceive) - beforeBal;
        require(received == amount, "phil did not receive amount");
        require(settlement.isSettled(paymentId), "not settled");
        console2.log("A2A PAYMENT COMPLETE");
        console2.log("amount", amount);
        console2.log("nonce", nonce);
        console2.log("philReceive", philReceive);
        console2.log("settlement", address(settlement));
    }

    /// @dev Shared Bob agent + global caps were sized for a single 20 USDC demo.
    ///      New onboarded users all settle as Bob → Phil, so raise ceilings before each pay.
    function _ensureCapacity(SohoSettlement settlement, IERC20 usdc, uint256 amount) internal {
        uint96 perTx = uint96(amount > 10_000e6 ? amount : 10_000e6);
        uint96 daily = 100_000_000e6;
        settlement.setTierCeilings(2, perTx, daily);
        settlement.setAgentTier(BOB_AGENT_ID, 2, perTx, daily);
        settlement.setGlobalDailyCap(daily);
        settlement.setGlobalOutstandingCap(500_000_000e6);
        if (usdc.balanceOf(address(settlement)) < amount) {
            MockUSDC(address(usdc)).mint(address(settlement), 10_000e6);
        }
    }

    function _sign(uint256 sk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(sk, digest);
        return abi.encodePacked(r, ss, vv);
    }
}
