// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";

/// @title  ISohoEvents — single declaration site for the SohoSettlement event surface (spec §3)
/// @notice These events are emitted from the composed base modules (IdentityRegistry,
///         MerchantRegistry) AND are part of the ISohoSettlement integration surface. Both
///         inherit this interface so each event has exactly ONE declaration — declaring an
///         event in two contracts that meet in SohoSettlement is a hard compile error
///         (9097: Identifier already declared). See docs/DECISIONS.md D-EVENTS-1.
interface ISohoEvents {
    event SettlementExecuted(
        bytes32 indexed paymentId,
        bytes32 indexed agentId,
        bytes32 indexed merchantId,
        address asset,
        uint256 amount,
        uint256 feeAmount,
        bytes32 orderRef
    );
    event PaymentRevoked(bytes32 indexed paymentId);
    event RepaymentReceived(bytes32 indexed agentId, uint256 amount, address payer);
    event OwnerRegistered(bytes32 indexed ownerId);
    event BusinessRegistered(bytes32 indexed businessId, bytes32 indexed ownerId);
    event AgentRegistered(bytes32 indexed agentId, bytes32 indexed businessId, address signer, uint8 tier);
    event AgentSignerRotated(bytes32 indexed agentId, address oldSigner, address newSigner);
    event TierChanged(bytes32 indexed agentId, uint8 tier, uint96 perTxCap, uint96 dailyCap);
    event AgentStatusChanged(bytes32 indexed agentId, Types.Status status);
    event AgentRevoked(bytes32 indexed agentId);
    event DefaultMarked(bytes32 indexed agentId, uint256 outstandingDebt);
    event MerchantRegistered(bytes32 indexed merchantId, address payout);
    event MerchantStatusChanged(bytes32 indexed merchantId, Types.Status status);
    event MerchantPayoutChanged(bytes32 indexed merchantId, address oldPayout, address newPayout);
    event TrustedSignerSet(address indexed signer, bool trusted);
    event CapUpdated(bytes32 indexed scope, uint256 newValue);
}
