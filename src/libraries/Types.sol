// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title  Types — SOHOPay v1 shared structs, enums, roles, errors (plan Rev 5)
/// @dev    FROZEN at design freeze. Changes here invalidate signed messages / storage
///         layout and trigger re-audit. Spec §2.
library Types {
    // Revoked/Defaulted apply to agents.
    enum Status {
        None,
        Active,
        Paused,
        Defaulted,
        Revoked
    }

    // ── Signed structs (EIP-712); hashing in SohoEIP712.sol ──
    struct PaymentIntent {
        bytes32 agentId;
        bytes32 merchantId;
        address asset;
        uint256 amount;
        uint256 feeAmount;
        bytes32 orderRef;
        uint256 nonce;
        uint256 deadline;
    }

    struct CreditAttestation {
        bytes32 paymentId;
        bytes32 agentId;
        address asset;
        uint256 amount;
        uint256 feeAmount;
        uint256 deadline;
    }

    // ── Identity chain (D-LIAB): Owner (KYC) → Business (KYB) → Agent (KYA) ──
    struct Owner {
        Status status; // KYC'd natural person
    }

    struct Business {
        bytes32 ownerId; // KYB'd legal borrower (EIN)
        Status status;
    }

    struct Agent {
        bytes32 businessId; // 0x0 only for anonymous Tier-0/1 (dormant at launch, D0)
        address signer; // Turnkey MPC EOA (current)
        uint8 tier; // 0=ERC8004 micro, 1=earned, 2=operator-bound (only 2 at launch)
        uint96 perTxCap;
        uint96 dailyCap;
        uint96 outstandingDebt;
        uint64 mandateExpiry; // tier-2 owner-signed delegation
        bytes32 mandateHash;
        Status status; // Active / Paused / Revoked / Defaulted
        uint96 dailySpent; // block.timestamp window
        uint64 windowStart;
    }

    struct Merchant {
        // single asset ⇒ no per-asset field; closed-loop target
        address payout;
        uint96 dailyCap;
        uint96 dailySpent;
        uint64 windowStart;
        Status status;
    }

    struct RedeemRequest {
        address owner;
        address receiver;
        uint256 shares;
        uint64 unlockAt;
        bool claimed;
        bool cancelled;
    }

    // ── Roles (OZ AccessControl; admin = TreasuryController) ──
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CREDIT_ADMIN_ROLE = keccak256("CREDIT_ADMIN_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // ── Errors ──
    error InvalidSignature();
    error UntrustedAttestationSigner();
    error IntentSignerMismatch(bytes32 agentId, address expected, address recovered);
    error AttestationIntentMismatch();
    error PaymentAlreadySettled(bytes32 paymentId);
    error PaymentRevokedError(bytes32 paymentId);
    error IntentExpired();
    error AttestationExpired();
    error AgentNotActive(bytes32 agentId);
    error AgentRevoked(bytes32 agentId); // D-REVOKE
    error BusinessNotActive(bytes32 businessId); // tier-2 identity chain
    error OwnerNotActive(bytes32 ownerId);
    error MandateExpired(bytes32 agentId);
    error MerchantNotActive(bytes32 merchantId); // CLOSED-LOOP (D-CLOSEDLOOP / I6)
    error UnsupportedAsset(address asset);
    error PerTxCapExceeded(uint256 amount, uint256 cap);
    error DailyCapExceeded(bytes32 scope);
    error GlobalCumulativeCapExceeded(); // D5 / I5
    error InsufficientFacilitatorBalance();
    error NotAuthorized();
    error ZeroAddress();
    error CapAboveTierCeiling(uint8 tier);
    error LastTrustedSigner();
    error GuardianSignerOverlap(); // INV-8
    error CooldownNotElapsed(uint256 requestId);
    error SharesLocked(uint256 requestId);
    error EpochAllowanceExceeded(address owner);
}
