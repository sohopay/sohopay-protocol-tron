// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";
import {ISohoEvents} from "./ISohoEvents.sol";

/// @title  ISohoSettlement — external surface of SohoSettlement (spec §3)
/// @notice The integration contract for the off-chain team (submission service, indexer)
///         and the in-system call surface. All shared structs/enums/errors come from
///         Types.sol; none are redefined here. Events live in ISohoEvents (single
///         declaration site, shared with the base modules). Function shapes per spec §3.
interface ISohoSettlement is ISohoEvents {
    // ===== SETTLEMENT (EXECUTOR_ROLE) =====
    function settleWithAttestation(
        Types.PaymentIntent calldata intent,
        bytes calldata intentSig,
        Types.CreditAttestation calldata att,
        bytes calldata attSig,
        address attestationSigner // DECISION(gate-1): attestation signer passed EXPLICITLY (EIP-1271-clean)
    ) external returns (bytes32 paymentId);

    /// @notice Additive A2A settlement (INV-A2A). Pays `_agentReceive[payeeAgentId]` of an
    ///         Active registered agent. Does not touch MerchantRegistry. Experimental.
    function settleAgentToAgent(
        Types.AgentPaymentIntent calldata intent,
        bytes calldata intentSig,
        Types.CreditAttestation calldata att,
        bytes calldata attSig,
        address attestationSigner
    ) external returns (bytes32 paymentId);

    function setAgentReceive(bytes32 agentId, address receive_) external; // TREASURY_ROLE
    function agentReceive(bytes32 agentId) external view returns (address);

    function revokePayment(bytes32 paymentId) external; // CREDIT_ADMIN_ROLE

    // ===== REPAYMENT (borrower-initiated only — D8; permissionless payer, USDC) =====
    function repay(bytes32 agentId, uint256 amount) external;

    // ===== IDENTITY CHAIN REGISTRIES =====
    function registerOwner(bytes32 ownerId) external; // TREASURY
    function registerBusiness(bytes32 businessId, bytes32 ownerId) external; // TREASURY
    function registerAgent( // CREDIT_ADMIN
        bytes32 agentId,
        bytes32 businessId,
        address signer,
        uint8 tier,
        uint96 perTxCap,
        uint96 dailyCap,
        uint64 mandateExpiry,
        bytes32 mandateHash
    ) external;
    function rotateAgentSigner(bytes32 agentId, address newSigner) external; // CREDIT_ADMIN
    function setAgentTier(bytes32 agentId, uint8 tier, uint96 perTxCap, uint96 dailyCap) external;
    function setAgentStatus(bytes32 agentId, Types.Status s) external;
    function revokeAgent(bytes32 agentId) external; // D-REVOKE
    function markDefault(bytes32 agentId) external; // CREDIT_ADMIN via timelock

    // ===== MERCHANTS (closed-loop, D-CLOSEDLOOP) =====
    function registerMerchant(bytes32 merchantId, address payout, uint96 dailyCap) external; // TREASURY
    function setMerchantPayout(bytes32 merchantId, address newPayout) external; // TREASURY
    function setMerchantStatus(bytes32 merchantId, Types.Status s) external;

    // ===== CAPS & CONFIG (TREASURY via TreasuryController) =====
    function setTierCeilings(uint8 tier, uint96 perTx, uint96 daily) external;
    function setGlobalDailyCap(uint96 cap) external;
    function setGlobalOutstandingCap(uint96 cap) external; // D5 / I5
    function setSupportedAsset(address asset, bool supported) external;
    function setTrustedSigner(address signer, bool trusted) external; // non-empty; INV-8 overlap guard
    function setFeeRecipient(address recipient) external;
    function setVault(address vault) external;

    // ===== PAUSE =====
    function pause() external; // GUARDIAN — global
    function unpause() external; // TREASURY only
    function pauseMerchant(bytes32 id) external; // GUARDIAN
    function pauseAgent(bytes32 id) external; // GUARDIAN

    // ===== VIEWS =====
    function computePaymentId(Types.PaymentIntent calldata intent) external view returns (bytes32);
    function computeAgentPaymentId(Types.AgentPaymentIntent calldata intent) external view returns (bytes32);
    function intentDigest(Types.PaymentIntent calldata intent) external view returns (bytes32);
    function agentIntentDigest(Types.AgentPaymentIntent calldata intent) external view returns (bytes32);
    function attestationDigest(Types.CreditAttestation calldata att) external view returns (bytes32);
    function isSettled(bytes32 paymentId) external view returns (bool);
    function isRevoked(bytes32 paymentId) external view returns (bool);
    function getAgent(bytes32 agentId) external view returns (Types.Agent memory);
    function getMerchant(bytes32 merchantId) external view returns (Types.Merchant memory);
    function globalOutstanding() external view returns (uint96);

    /// @notice EIP-5267 — domain binds to the proxy address (spec §1.1).
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    // ===== EVENTS — declared in ISohoEvents (inherited) =====
}
