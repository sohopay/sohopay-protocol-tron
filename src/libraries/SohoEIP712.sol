// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "./Types.sol";

/// @title  SohoEIP712
/// @notice Typehashes and struct-hash helpers for PaymentIntent and CreditAttestation.
/// @dev    Spec §1. FULLY IMPLEMENTED — these encodings are frozen; any change breaks
///         every signed message in flight and requires re-audit.
///
///         Domain (owned by SohoSettlement, OZ EIP712 base):
///           name = "SohoSettlement", version = "1",
///           chainId + verifyingContract from the deployment — NEVER in structs.
///
///         paymentId = hashStruct(PaymentIntent) is the canonical payment identifier
///         AND the single replay key (spec §0): one intent → one paymentId → at most
///         one settlement, regardless of how many attestations are issued for it.
library SohoEIP712 {
    /// @dev keccak256 of the exact type string — field order is normative.
    bytes32 internal constant PAYMENT_INTENT_TYPEHASH = keccak256(
        "PaymentIntent(bytes32 agentId,bytes32 merchantId,address asset,uint256 amount,uint256 feeAmount,bytes32 orderRef,uint256 nonce,uint256 deadline)"
    );

    bytes32 internal constant CREDIT_ATTESTATION_TYPEHASH = keccak256(
        "CreditAttestation(bytes32 paymentId,bytes32 agentId,address asset,uint256 amount,uint256 feeAmount,uint256 deadline)"
    );

    /// @notice hashStruct(PaymentIntent) — this IS the paymentId.
    function hashIntent(Types.PaymentIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PAYMENT_INTENT_TYPEHASH,
                intent.agentId,
                intent.merchantId,
                intent.asset,
                intent.amount,
                intent.feeAmount,
                intent.orderRef,
                intent.nonce,
                intent.deadline
            )
        );
    }

    /// @notice hashStruct(CreditAttestation).
    function hashAttestation(Types.CreditAttestation calldata att) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CREDIT_ATTESTATION_TYPEHASH,
                att.paymentId,
                att.agentId,
                att.asset,
                att.amount,
                att.feeAmount,
                att.deadline
            )
        );
    }
}
