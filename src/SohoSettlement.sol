// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    EIP712Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Types} from "./libraries/Types.sol";
import {SohoEIP712} from "./libraries/SohoEIP712.sol";
import {IdentityRegistry} from "./base/IdentityRegistry.sol";
import {MerchantRegistry} from "./base/MerchantRegistry.sol";
import {CapManager} from "./base/CapManager.sol";
import {PayeeAgentNotActive, PayeeReceiveUnset, SelfPayment} from "./base/RegistryErrors.sol";
import {ISohoVault} from "./interfaces/ISohoVault.sol";
import {ISohoSettlement} from "./interfaces/ISohoSettlement.sol";

/// @title  SohoSettlement (UUPS upgradeable — plan Rev 5)
/// @notice The settlement gate. Verifies agent PaymentIntent + CreditManager
///         CreditAttestation, binds via paymentId, consumes the replay key, enforces
///         on-chain per-tx / daily / CUMULATIVE caps, pays a REGISTERED merchant only
///         (CLOSED-LOOP, D-CLOSEDLOOP). Absorbs former SettlementExecutor / Facilitator /
///         Borrower / Merchant managers. Single asset (USDC). No RepaymentRouter.
/// @dev    Credit decisions are backend-trusted (chain verifies THAT the signer signed).
///         Upgradeable via TreasuryController + timelock (D14); Guardian-pausable.
///         Storage append-only; __gap reserved.
contract SohoSettlement is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable,
    CapManager,
    MerchantRegistry,
    IdentityRegistry,
    ISohoSettlement
{
    using SafeERC20 for IERC20;

    mapping(bytes32 => bool) public usedPayments; // INV-1 replay key (= paymentId)
    mapping(bytes32 => bool) public revokedPayments; // INV-10
    mapping(address => bool) public trustedSigners; // EIP-1271-capable; never empty (INV-8)
    uint256 internal _trustedSignerCount;
    mapping(address => bool) public isSupportedAsset; // single entry (USDC) v1
    address public usdc;
    address public feeRecipient;
    address public vault;
    address public treasuryController; // upgrade authority (D14)
    /// @dev Additive A2A receive wallets. Appended after existing Settlement slots;
    ///      consumes 1 slot from `__gap` (40 → 39). Never defaults to `agent.signer`.
    mapping(bytes32 => address) internal _agentReceive;

    /// @dev DECISION(gate-1): direct-repay overpayment REVERTS (O10, recommended default).
    error Overpayment(bytes32 agentId, uint256 amount, uint256 outstandingDebt);

    // Settlement events (SettlementExecuted, PaymentRevoked, RepaymentReceived,
    // TrustedSignerSet) are declared in ISohoEvents (inherited via ISohoSettlement).
    // These two are settlement-only config events not in the spec's §3 surface:
    event FeeRecipientSet(address indexed recipient);
    event AssetSupportSet(address indexed asset, bool supported);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address controller, address usdc_, address vault_, address feeRecipient_)
        external
        initializer
    {
        if (
            controller == address(0) || usdc_ == address(0) || vault_ == address(0)
                || feeRecipient_ == address(0)
        ) {
            revert Types.ZeroAddress();
        }
        __AccessControl_init();
        __Pausable_init();
        __EIP712_init("SohoSettlement", "1");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, controller);
        _grantRole(Types.TREASURY_ROLE, controller);

        treasuryController = controller;
        usdc = usdc_;
        vault = vault_;
        feeRecipient = feeRecipient_;
    }

    /// @dev D14: only the TreasuryController (timelocked, Guardian-pausable) may upgrade.
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != treasuryController) revert Types.NotAuthorized();
    }

    // ===== SETTLEMENT — spec §3.1 normative 19-step order. DO NOT REORDER. =====
    function settleWithAttestation(
        Types.PaymentIntent calldata intent,
        bytes calldata intentSig,
        Types.CreditAttestation calldata att,
        bytes calldata attSig,
        address attestationSigner // DECISION(gate-1): attestation signer passed EXPLICITLY (EIP-1271-clean)
    ) external whenNotPaused onlyRole(Types.EXECUTOR_ROLE) returns (bytes32 paymentId) {
        // 1. whenNotPaused; onlyRole(EXECUTOR_ROLE)  (modifiers above)
        // 2. paymentId = hashStruct(intent)
        paymentId = SohoEIP712.hashIntent(intent);
        // 3. not already settled
        if (usedPayments[paymentId]) revert Types.PaymentAlreadySettled(paymentId);
        // 4. not revoked
        if (revokedPayments[paymentId]) revert Types.PaymentRevokedError(paymentId);
        // 5. intent not expired
        if (block.timestamp > intent.deadline) revert Types.IntentExpired();
        // 6. attestation not expired
        if (block.timestamp > att.deadline) revert Types.AttestationExpired();
        // 7. binding cross-check: att.paymentId==paymentId; att.* == intent.*
        if (
            att.paymentId != paymentId || att.agentId != intent.agentId || att.asset != intent.asset
                || att.amount != intent.amount || att.feeAmount != intent.feeAmount
        ) revert Types.AttestationIntentMismatch();
        // 8. agent Active && !Revoked; tier-2 (launch): business + owner Active, mandate valid
        Types.Agent storage agent = _agents[intent.agentId];
        if (agent.status == Types.Status.Revoked) revert Types.AgentRevoked(intent.agentId);
        if (agent.status != Types.Status.Active) revert Types.AgentNotActive(intent.agentId);
        if (agent.tier == 2) {
            Types.Business storage business = _businesses[agent.businessId];
            if (business.status != Types.Status.Active) revert Types.BusinessNotActive(agent.businessId);
            if (_owners[business.ownerId].status != Types.Status.Active) {
                revert Types.OwnerNotActive(business.ownerId);
            }
            if (block.timestamp > agent.mandateExpiry) revert Types.MandateExpired(intent.agentId);
        }
        // 9. CLOSED-LOOP: merchant Active (D-CLOSEDLOOP / INV-6L)
        Types.Merchant storage merchant = _merchants[intent.merchantId];
        if (merchant.status != Types.Status.Active) revert Types.MerchantNotActive(intent.merchantId);
        // 10. supported asset
        if (!isSupportedAsset[intent.asset]) revert Types.UnsupportedAsset(intent.asset);
        // 11. intent sig == agent.signer (ECDSA, never ecrecover)
        {
            address recovered = ECDSA.recover(_hashTypedDataV4(paymentId), intentSig);
            if (recovered != agent.signer) {
                revert Types.IntentSignerMismatch(intent.agentId, agent.signer, recovered);
            }
        }
        // 12. attestation sig trusted (SignatureChecker, EIP-1271 ok); explicit signer checked
        {
            if (!trustedSigners[attestationSigner]) revert Types.UntrustedAttestationSigner();
            bytes32 attDigest = _hashTypedDataV4(SohoEIP712.hashAttestation(att));
            if (!SignatureChecker.isValidSignatureNow(attestationSigner, attDigest, attSig)) {
                revert Types.InvalidSignature();
            }
        }
        // 13. caps (CHECK ONLY): per-tx + daily windows on amount; cumulative on amount+fee
        if (intent.amount > type(uint96).max) revert Types.PerTxCapExceeded(intent.amount, agent.perTxCap);
        if (intent.feeAmount > type(uint96).max) revert Types.GlobalCumulativeCapExceeded();
        uint256 total = intent.amount + intent.feeAmount; // each <= uint96 max ⇒ no uint256 overflow
        if (total > type(uint96).max) revert Types.GlobalCumulativeCapExceeded();
        uint96 amount96 = uint96(intent.amount);
        uint96 total96 = uint96(total);
        _checkCaps(agent, merchant, amount96);
        _checkGlobalOutstanding(total96);
        // 14. hot-float balance >= amount + fee
        if (IERC20(usdc).balanceOf(address(this)) < intent.amount + intent.feeAmount) {
            revert Types.InsufficientFacilitatorBalance();
        }

        // --- EFFECTS (before interactions — CEI) ---
        // 15. consume the replay key
        usedPayments[paymentId] = true;
        // 16. accrue daily windows; globalOutstanding += amount+fee; agent.outstandingDebt += amount+fee
        _accrueCaps(agent, merchant, amount96);
        _accrueOutstanding(total96);
        agent.outstandingDebt += total96;

        // --- INTERACTIONS ---
        // 17. payout to the registered (closed-loop) merchant
        IERC20(usdc).safeTransfer(merchant.payout, intent.amount);
        // 18. protocol fee
        IERC20(usdc).safeTransfer(feeRecipient, intent.feeAmount);
        // 19. emit
        emit SettlementExecuted(
            paymentId,
            intent.agentId,
            intent.merchantId,
            intent.asset,
            intent.amount,
            intent.feeAmount,
            intent.orderRef
        );
    }

    /// @notice Additive A2A settlement (INV-A2A). Parallel to settleWithAttestation.
    ///         Pays `_agentReceive[payee]` of an Active registered agent. Does not read
    ///         or write MerchantRegistry. Experimental — not covered by the prior v1 audit.
    /// @dev    Check order mirrors the merchant 19-step CEI (sigs + caps + hot-float before
    ///         effects; transfers after consume). DO NOT weaken replay or signature gates.
    function settleAgentToAgent(
        Types.AgentPaymentIntent calldata intent,
        bytes calldata intentSig,
        Types.CreditAttestation calldata att,
        bytes calldata attSig,
        address attestationSigner
    ) external whenNotPaused onlyRole(Types.EXECUTOR_ROLE) returns (bytes32 paymentId) {
        // 1. whenNotPaused; onlyRole(EXECUTOR_ROLE)
        // 2. paymentId = hashStruct(AgentPaymentIntent) — domain-separated from merchant intents
        paymentId = SohoEIP712.hashAgentIntent(intent);
        // 3. not already settled
        if (usedPayments[paymentId]) revert Types.PaymentAlreadySettled(paymentId);
        // 4. not revoked
        if (revokedPayments[paymentId]) revert Types.PaymentRevokedError(paymentId);
        // 5. intent not expired
        if (block.timestamp > intent.deadline) revert Types.IntentExpired();
        // 6. attestation not expired
        if (block.timestamp > att.deadline) revert Types.AttestationExpired();
        // 7. binding: att.paymentId==paymentId binds payee (inside the A2A hash); att.* == payer fields
        if (
            att.paymentId != paymentId || att.agentId != intent.payerAgentId || att.asset != intent.asset
                || att.amount != intent.amount || att.feeAmount != intent.feeAmount
        ) revert Types.AttestationIntentMismatch();
        // 8. payer Active && !Revoked; tier-2 (launch): business + owner Active, mandate valid
        Types.Agent storage payer = _agents[intent.payerAgentId];
        if (payer.status == Types.Status.Revoked) revert Types.AgentRevoked(intent.payerAgentId);
        if (payer.status != Types.Status.Active) revert Types.AgentNotActive(intent.payerAgentId);
        if (payer.tier == 2) {
            Types.Business storage payerBiz = _businesses[payer.businessId];
            if (payerBiz.status != Types.Status.Active) revert Types.BusinessNotActive(payer.businessId);
            if (_owners[payerBiz.ownerId].status != Types.Status.Active) {
                revert Types.OwnerNotActive(payerBiz.ownerId);
            }
            if (block.timestamp > payer.mandateExpiry) revert Types.MandateExpired(intent.payerAgentId);
        }
        // 9. payee is a registered Active agent (not a merchant). Mandate is payer-only.
        //    Tier-2: require Active business + owner so receive is gated by the identity chain.
        if (intent.payerAgentId == intent.payeeAgentId) revert SelfPayment(intent.payerAgentId);
        Types.Agent storage payee = _agents[intent.payeeAgentId];
        if (payee.status == Types.Status.Revoked) revert Types.AgentRevoked(intent.payeeAgentId);
        if (payee.status != Types.Status.Active) revert PayeeAgentNotActive(intent.payeeAgentId);
        if (payee.tier == 2) {
            Types.Business storage payeeBiz = _businesses[payee.businessId];
            if (payeeBiz.status != Types.Status.Active) revert Types.BusinessNotActive(payee.businessId);
            if (_owners[payeeBiz.ownerId].status != Types.Status.Active) {
                revert Types.OwnerNotActive(payeeBiz.ownerId);
            }
        }
        // 10. receive address configured — never fall back to payee.signer
        address receiveAddr = _agentReceive[intent.payeeAgentId];
        if (receiveAddr == address(0)) revert PayeeReceiveUnset(intent.payeeAgentId);
        // 11. supported asset
        if (!isSupportedAsset[intent.asset]) revert Types.UnsupportedAsset(intent.asset);
        // 12. intent sig == payer.signer (ECDSA, never ecrecover)
        {
            address recovered = ECDSA.recover(_hashTypedDataV4(paymentId), intentSig);
            if (recovered != payer.signer) {
                revert Types.IntentSignerMismatch(intent.payerAgentId, payer.signer, recovered);
            }
        }
        // 13. attestation sig trusted (SignatureChecker, EIP-1271 ok); explicit signer checked
        {
            if (!trustedSigners[attestationSigner]) revert Types.UntrustedAttestationSigner();
            bytes32 attDigest = _hashTypedDataV4(SohoEIP712.hashAttestation(att));
            if (!SignatureChecker.isValidSignatureNow(attestationSigner, attDigest, attSig)) {
                revert Types.InvalidSignature();
            }
        }
        // 14. caps (CHECK ONLY): per-tx + payer/global daily on amount; cumulative on amount+fee
        if (intent.amount > type(uint96).max) revert Types.PerTxCapExceeded(intent.amount, payer.perTxCap);
        if (intent.feeAmount > type(uint96).max) revert Types.GlobalCumulativeCapExceeded();
        uint256 total = intent.amount + intent.feeAmount;
        if (total > type(uint96).max) revert Types.GlobalCumulativeCapExceeded();
        uint96 amount96 = uint96(intent.amount);
        uint96 total96 = uint96(total);
        _checkPayerCaps(payer, amount96);
        _checkGlobalOutstanding(total96);
        // 15. hot-float balance >= amount + fee
        if (IERC20(usdc).balanceOf(address(this)) < intent.amount + intent.feeAmount) {
            revert Types.InsufficientFacilitatorBalance();
        }

        // --- EFFECTS (before interactions — CEI) ---
        // 16. consume the replay key
        usedPayments[paymentId] = true;
        // 17. accrue payer + global daily; no merchant window
        _accruePayerCaps(payer, amount96);
        _accrueOutstanding(total96);
        payer.outstandingDebt += total96;

        // --- INTERACTIONS ---
        // 18. payout to the configured agent receive address (not signer, not merchant.payout)
        IERC20(usdc).safeTransfer(receiveAddr, intent.amount);
        // 19. protocol fee
        IERC20(usdc).safeTransfer(feeRecipient, intent.feeAmount);
        // 20. emit A2A-specific event (do not overload SettlementExecuted)
        emit AgentToAgentSettled(
            paymentId,
            intent.payerAgentId,
            intent.payeeAgentId,
            intent.asset,
            intent.amount,
            intent.feeAmount,
            intent.orderRef
        );
    }

    /// @notice TREASURY sets the A2A receive wallet. Zero address and unknown agents revert.
    function setAgentReceive(bytes32 agentId, address receive_) external onlyRole(Types.TREASURY_ROLE) {
        if (receive_ == address(0)) revert Types.ZeroAddress();
        if (_agents[agentId].status == Types.Status.None) revert Types.AgentNotActive(agentId);
        address old = _agentReceive[agentId];
        _agentReceive[agentId] = receive_;
        emit AgentReceiveSet(agentId, old, receive_);
    }

    function agentReceive(bytes32 agentId) external view returns (address) {
        return _agentReceive[agentId];
    }

    function revokePayment(bytes32 paymentId) external onlyRole(Types.CREDIT_ADMIN_ROLE) {
        if (usedPayments[paymentId]) revert Types.PaymentAlreadySettled(paymentId); // can't revoke a settled payment
        revokedPayments[paymentId] = true; // INV-10: revoked can never settle (step 4)
        emit PaymentRevoked(paymentId);
    }

    // ===== REPAYMENT (borrower-initiated; no router — D8) =====
    function repay(bytes32 agentId, uint256 amount) external {
        Types.Agent storage agent = _agents[agentId];
        if (agent.status == Types.Status.None) revert Types.AgentNotActive(agentId);
        uint256 debt = agent.outstandingDebt;
        // DECISION(gate-1): overpayment REVERTS (O10) — no credit balance is created.
        if (amount > debt) revert Overpayment(agentId, amount, debt);

        // effects: reduce the agent's debt and the cumulative exposure
        agent.outstandingDebt = uint96(debt - amount);
        _releaseOutstanding(uint96(amount));

        // interactions: forward USDC payer -> vault, then notify (spec §3.2)
        IERC20(usdc).safeTransferFrom(msg.sender, vault, amount);
        ISohoVault(vault).receiveRepayment(amount, agentId);
        emit RepaymentReceived(agentId, amount, msg.sender);
    }

    // ===== IDENTITY CHAIN =====
    function registerOwner(bytes32 id) external onlyRole(Types.TREASURY_ROLE) {
        _registerOwner(id);
    }

    function registerBusiness(bytes32 id, bytes32 ownerId) external onlyRole(Types.TREASURY_ROLE) {
        _registerBusiness(id, ownerId);
    }

    function registerAgent(
        bytes32 a,
        bytes32 b,
        address s,
        uint8 t,
        uint96 px,
        uint96 d,
        uint64 me,
        bytes32 mh
    ) external onlyRole(Types.CREDIT_ADMIN_ROLE) {
        _registerAgent(a, b, s, t, px, d, me, mh);
    }

    function rotateAgentSigner(bytes32 a, address s) external onlyRole(Types.CREDIT_ADMIN_ROLE) {
        _rotateAgentSigner(a, s);
    }

    function setAgentTier(bytes32 a, uint8 t, uint96 px, uint96 d)
        external
        onlyRole(Types.CREDIT_ADMIN_ROLE)
    {
        _setAgentTier(a, t, px, d);
    }

    /// @dev Unpause (->Active): TREASURY. Pause (->Paused): GUARDIAN or CREDIT_ADMIN. Other
    ///      targets are rejected by _setAgentStatus (terminal states use revoke/markDefault).
    function setAgentStatus(bytes32 a, Types.Status s) external {
        if (s == Types.Status.Active) {
            if (!hasRole(Types.TREASURY_ROLE, msg.sender)) revert Types.NotAuthorized();
        } else if (s == Types.Status.Paused) {
            if (!hasRole(Types.GUARDIAN_ROLE, msg.sender) && !hasRole(Types.CREDIT_ADMIN_ROLE, msg.sender)) {
                revert Types.NotAuthorized();
            }
        }
        _setAgentStatus(a, s);
    }

    function revokeAgent(bytes32 a) external onlyRole(Types.CREDIT_ADMIN_ROLE) {
        _revokeAgent(a);
    }

    function markDefault(bytes32 a) external onlyRole(Types.CREDIT_ADMIN_ROLE) {
        _markDefault(a);
    }

    // ===== MERCHANTS (closed-loop) =====
    function registerMerchant(bytes32 id, address payout, uint96 d) external onlyRole(Types.TREASURY_ROLE) {
        _registerMerchant(id, payout, d);
    }

    function setMerchantPayout(bytes32 id, address p) external onlyRole(Types.TREASURY_ROLE) {
        _setMerchantPayout(id, p);
    }

    /// @dev Unpause (->Active): TREASURY. Pause (->Paused): GUARDIAN or TREASURY.
    function setMerchantStatus(bytes32 id, Types.Status s) external {
        if (s == Types.Status.Active) {
            if (!hasRole(Types.TREASURY_ROLE, msg.sender)) revert Types.NotAuthorized();
        } else if (s == Types.Status.Paused) {
            if (!hasRole(Types.GUARDIAN_ROLE, msg.sender) && !hasRole(Types.TREASURY_ROLE, msg.sender)) {
                revert Types.NotAuthorized();
            }
        }
        _setMerchantStatus(id, s);
    }

    // ===== CAPS & CONFIG =====
    function setTierCeilings(uint8 t, uint96 px, uint96 d) external onlyRole(Types.TREASURY_ROLE) {
        _setTierCeilings(t, px, d);
    }

    function setGlobalDailyCap(uint96 c) external onlyRole(Types.TREASURY_ROLE) {
        _setGlobalDailyCap(c);
    }

    function setGlobalOutstandingCap(uint96 c) external onlyRole(Types.TREASURY_ROLE) {
        _setGlobalOutstandingCap(c);
    }

    function setSupportedAsset(address a, bool ok) external onlyRole(Types.TREASURY_ROLE) {
        if (ok && a == address(0)) revert Types.ZeroAddress();
        isSupportedAsset[a] = ok;
        emit AssetSupportSet(a, ok);
    }

    /// @dev INV-8: the trusted-signer set is never emptied (LastTrustedSigner) and no address
    ///      may simultaneously hold GUARDIAN_ROLE and be a trusted signer (GuardianSignerOverlap).
    function setTrustedSigner(address signer, bool trusted) external onlyRole(Types.TREASURY_ROLE) {
        if (signer == address(0)) revert Types.ZeroAddress();
        if (trusted) {
            if (hasRole(Types.GUARDIAN_ROLE, signer)) revert Types.GuardianSignerOverlap();
            if (!trustedSigners[signer]) {
                trustedSigners[signer] = true;
                _trustedSignerCount += 1;
            }
        } else {
            if (trustedSigners[signer]) {
                if (_trustedSignerCount <= 1) revert Types.LastTrustedSigner();
                trustedSigners[signer] = false;
                _trustedSignerCount -= 1;
            }
        }
        emit TrustedSignerSet(signer, trusted);
    }

    function setFeeRecipient(address r) external onlyRole(Types.TREASURY_ROLE) {
        if (r == address(0)) revert Types.ZeroAddress();
        feeRecipient = r;
        emit FeeRecipientSet(r);
    }

    function setVault(address v) external onlyRole(Types.TREASURY_ROLE) {
        if (v == address(0)) revert Types.ZeroAddress();
        vault = v;
    }

    // ===== PAUSE =====
    function pause() external onlyRole(Types.GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Types.TREASURY_ROLE) {
        _unpause();
    }

    function pauseMerchant(bytes32 id) external onlyRole(Types.GUARDIAN_ROLE) {
        _setMerchantStatus(id, Types.Status.Paused);
    }

    function pauseAgent(bytes32 id) external onlyRole(Types.GUARDIAN_ROLE) {
        _setAgentStatus(id, Types.Status.Paused);
    }

    // ===== VIEWS =====
    function computePaymentId(Types.PaymentIntent calldata i) external pure returns (bytes32) {
        return SohoEIP712.hashIntent(i);
    }

    function computeAgentPaymentId(Types.AgentPaymentIntent calldata i) external pure returns (bytes32) {
        return SohoEIP712.hashAgentIntent(i);
    }

    function intentDigest(Types.PaymentIntent calldata i) external view returns (bytes32) {
        return _hashTypedDataV4(SohoEIP712.hashIntent(i));
    }

    function agentIntentDigest(Types.AgentPaymentIntent calldata i) external view returns (bytes32) {
        return _hashTypedDataV4(SohoEIP712.hashAgentIntent(i));
    }

    function attestationDigest(Types.CreditAttestation calldata a) external view returns (bytes32) {
        return _hashTypedDataV4(SohoEIP712.hashAttestation(a));
    }

    function isSettled(bytes32 id) external view returns (bool) {
        return usedPayments[id];
    }

    function isRevoked(bytes32 id) external view returns (bool) {
        return revokedPayments[id];
    }

    function globalOutstanding() external view returns (uint96) {
        return _globalOutstanding;
    }

    // ── interface-disambiguation overrides (function present in a base AND ISohoSettlement) ──
    function getAgent(bytes32 id)
        public
        view
        override(IdentityRegistry, ISohoSettlement)
        returns (Types.Agent memory)
    {
        return super.getAgent(id);
    }

    function getMerchant(bytes32 id)
        public
        view
        override(MerchantRegistry, ISohoSettlement)
        returns (Types.Merchant memory)
    {
        return super.getMerchant(id);
    }

    function eip712Domain()
        public
        view
        override(EIP712Upgradeable, ISohoSettlement)
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return super.eip712Domain();
    }

    // ===== INV-8 enforcement (both directions) =====
    /// @dev Rejects granting GUARDIAN_ROLE to a current trusted signer (the setTrustedSigner
    ///      path guards the reverse direction). Together these uphold INV-8 with no overlap.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == Types.GUARDIAN_ROLE && trustedSigners[account]) revert Types.GuardianSignerOverlap();
        return super._grantRole(role, account);
    }

    /// @dev Upgrade-safety storage gap (D14). Append above; never reorder.
    ///      Slot consumed: `_agentReceive` (1 mapping). Before: 40. After: 39.
    uint256[39] private __gap;
}
