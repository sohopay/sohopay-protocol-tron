// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";
import {CapManager} from "./CapManager.sol";
import {ISohoEvents} from "../interfaces/ISohoEvents.sol";
import {AlreadyRegistered, SignerInUse, InvalidStatusTransition} from "./RegistryErrors.sol";

/// @title  IdentityRegistry (abstract module — inherited by SohoSettlement)
/// @notice Owner (KYC) -> Business (KYB) -> Agent (KYA) chain. Replaces the old
///         two-tier AgentRegistry. Plan Rev 5 §4.3 / §5.1; spec §3.
/// @dev    D-LIAB: Business/Owner is the legal borrower; Agent is operational actor.
///         D0: only tier-2 (business+owner-bound) active at launch. Anonymous Tier-0/1
///         paths (businessId == 0x0) are BUILT LAST and feature-flagged off until the
///         Gate-0 Tier-0 ruling + D-LIAB resolve (spec §9).
///         INV-9: rotated-out / revoked signer can never settle (signer read at verify).
///         Upgradeable: append-only storage; __gap reserved at the composing contract.
///
///         Inherits CapManager so tier-ceiling enforcement (CapAboveTierCeiling) reads the
///         single Treasury-owned ceiling source rather than a duplicated copy.
///
///         ── Error taxonomy (see docs/DECISIONS.md). Three classes, by who sees them:
///         (1) shared Types.sol errors — the frozen cross-contract surface (kept frozen);
///         (2) registry-local errors below — expected operator/backend failures that need
///             a clear, specific signal (re-registration, duplicate signer, bad status
///             transition); (3) generic Types.NotAuthorized() — internal "should never
///             happen in correct operation" guards (reserved 0x0 ids, missing tier-2
///             mandate, dormant anonymous tier), commented at each revert site.
abstract contract IdentityRegistry is CapManager, ISohoEvents {
    // registry-local errors (class 2) live in RegistryErrors.sol — see import above.
    // events live in ISohoEvents (single declaration site) — see import above.

    mapping(bytes32 => Types.Owner) internal _owners;
    mapping(bytes32 => Types.Business) internal _businesses;
    mapping(bytes32 => Types.Agent) internal _agents;
    mapping(address => bytes32) internal _signerToAgent; // 1:1 signer<->agent

    /// @dev D0/§9: anonymous Tier-0/1 (businessId==0x0) registration is gated OFF until the
    ///      Gate-0 legal ruling. No on-chain toggle is exposed in v1 — it stays false.
    bool internal _anonymousTierEnabled;

    // ── mutators (role checks wired at the SohoSettlement call site) ──

    function _registerOwner(bytes32 ownerId) internal {
        if (ownerId == bytes32(0)) revert Types.NotAuthorized(); // (3) 0x0 reserved as anon sentinel
        if (_owners[ownerId].status != Types.Status.None) revert AlreadyRegistered(ownerId); // (2)
        _owners[ownerId].status = Types.Status.Active;
        emit OwnerRegistered(ownerId);
    }

    function _registerBusiness(bytes32 businessId, bytes32 ownerId) internal {
        if (businessId == bytes32(0)) revert Types.NotAuthorized(); // (3) 0x0 reserved as anon sentinel
        if (_businesses[businessId].status != Types.Status.None) revert AlreadyRegistered(businessId); // (2)
        if (_owners[ownerId].status != Types.Status.Active) revert Types.OwnerNotActive(ownerId); // (1)
        _businesses[businessId] = Types.Business({ownerId: ownerId, status: Types.Status.Active});
        emit BusinessRegistered(businessId, ownerId);
    }

    function _registerAgent(
        bytes32 agentId,
        bytes32 businessId,
        address signer,
        uint8 tier,
        uint96 perTxCap,
        uint96 dailyCap,
        uint64 mandateExpiry,
        bytes32 mandateHash
    ) internal {
        if (_agents[agentId].status != Types.Status.None) revert AlreadyRegistered(agentId); // (2) create-only
        if (signer == address(0)) revert Types.ZeroAddress(); // (1)
        if (_signerToAgent[signer] != bytes32(0)) revert SignerInUse(signer); // (2) 1:1 signer<->agent

        if (tier == 2) {
            // ── LAUNCH PATH (D0): operator-bound. Requires Active Business + Active Owner,
            //    a non-zero owner-signed mandate, and a still-valid mandate window. ──
            if (businessId == bytes32(0)) revert Types.BusinessNotActive(businessId); // (1)
            Types.Business storage b = _businesses[businessId];
            if (b.status != Types.Status.Active) revert Types.BusinessNotActive(businessId); // (1)
            if (_owners[b.ownerId].status != Types.Status.Active) revert Types.OwnerNotActive(b.ownerId); // (1)
            if (mandateHash == bytes32(0)) revert Types.NotAuthorized(); // (3) backend invariant: tier-2 mandate
            if (mandateExpiry <= block.timestamp) revert Types.MandateExpired(agentId); // (1)
        } else {
            // ── ANONYMOUS / Tier-0/1: dormant at launch (D0 / §9). ──
            // TODO(gated): Tier-0/1 pending legal ruling per §9 — businessId==0x0 anonymous
            // path. Full tier-0/1 binding logic is intentionally not implemented until cleared.
            if (!_anonymousTierEnabled) revert Types.NotAuthorized(); // (3) dormant feature gate
        }

        // caps may never exceed the Treasury-set ceiling for the tier (CapManager source)
        TierCeiling memory ceiling = _tierCeilings[tier];
        if (perTxCap > ceiling.perTx || dailyCap > ceiling.daily) revert Types.CapAboveTierCeiling(tier);

        _agents[agentId] = Types.Agent({
            businessId: businessId,
            signer: signer,
            tier: tier,
            perTxCap: perTxCap,
            dailyCap: dailyCap,
            outstandingDebt: 0,
            mandateExpiry: mandateExpiry,
            mandateHash: mandateHash,
            status: Types.Status.Active,
            dailySpent: 0,
            windowStart: 0
        });
        _signerToAgent[signer] = agentId;
        emit AgentRegistered(agentId, businessId, signer, tier);
    }

    function _rotateAgentSigner(bytes32 agentId, address newSigner) internal {
        Types.Agent storage a = _agents[agentId];
        if (a.status == Types.Status.None) revert Types.AgentNotActive(agentId); // (1)
        if (a.status == Types.Status.Revoked) revert Types.AgentRevoked(agentId); // (1) terminal
        if (newSigner == address(0)) revert Types.ZeroAddress(); // (1)
        if (_signerToAgent[newSigner] != bytes32(0)) revert SignerInUse(newSigner); // (2) 1:1 uniqueness

        address oldSigner = a.signer;
        delete _signerToAgent[oldSigner]; // INV-9: rotated-out signer can never settle
        a.signer = newSigner;
        _signerToAgent[newSigner] = agentId;
        emit AgentSignerRotated(agentId, oldSigner, newSigner);
    }

    function _setAgentTier(bytes32 agentId, uint8 tier, uint96 perTxCap, uint96 dailyCap) internal {
        Types.Agent storage a = _agents[agentId];
        if (a.status == Types.Status.None) revert Types.AgentNotActive(agentId); // (1)
        if (a.status == Types.Status.Revoked) revert Types.AgentRevoked(agentId); // (1) terminal

        TierCeiling memory ceiling = _tierCeilings[tier];
        if (perTxCap > ceiling.perTx || dailyCap > ceiling.daily) revert Types.CapAboveTierCeiling(tier); // (1)

        a.tier = tier;
        a.perTxCap = perTxCap;
        a.dailyCap = dailyCap;
        emit TierChanged(agentId, tier, perTxCap, dailyCap);
    }

    function _setAgentStatus(bytes32 agentId, Types.Status s) internal {
        // Operational pause/unpause ONLY. Revoked/Defaulted are terminal and reached via the
        // dedicated _revokeAgent / _markDefault paths — never through this generic setter.
        Types.Agent storage a = _agents[agentId];
        Types.Status from = a.status;
        if (from == Types.Status.None) revert Types.AgentNotActive(agentId); // (1) no such agent
        // (2) terminal source, or a target that is not an operational state, is an invalid move
        bool operationalTarget = (s == Types.Status.Active || s == Types.Status.Paused);
        bool mutableSource = (from == Types.Status.Active || from == Types.Status.Paused);
        if (!operationalTarget || !mutableSource) revert InvalidStatusTransition(uint8(from), uint8(s));
        a.status = s;
        emit AgentStatusChanged(agentId, s);
    }

    function _revokeAgent(bytes32 agentId) internal {
        // D-REVOKE — owner-triggered via CREDIT_ADMIN. Revoked is TERMINAL for settlement
        // (step 8 fails forever); owner stays liable for pre-revocation outstandingDebt.
        Types.Agent storage a = _agents[agentId];
        if (a.status == Types.Status.None) revert Types.AgentNotActive(agentId); // (1)
        if (a.status == Types.Status.Revoked) revert Types.AgentRevoked(agentId); // (1) already terminal
        a.status = Types.Status.Revoked;
        emit AgentRevoked(agentId); // spec §3 event name (reconciled at wiring — D-IFACE-5)
    }

    function _markDefault(bytes32 agentId) internal {
        // Via TreasuryController timelock (dual-delay). Vault-side recognizeLoss covers from
        // reserve first. outstandingDebt is preserved (it is the loss figure).
        Types.Agent storage a = _agents[agentId];
        if (a.status == Types.Status.None) revert Types.AgentNotActive(agentId); // (1)
        if (a.status == Types.Status.Revoked) revert Types.AgentRevoked(agentId); // (1) terminal
        if (a.status == Types.Status.Defaulted) revert Types.AgentNotActive(agentId); // (1) already defaulted
        a.status = Types.Status.Defaulted;
        emit DefaultMarked(agentId, a.outstandingDebt);
    }

    // ── views ──
    function getAgent(bytes32 id) public view virtual returns (Types.Agent memory) {
        return _agents[id];
    }

    function getBusiness(bytes32 id) public view returns (Types.Business memory) {
        return _businesses[id];
    }

    function getOwner(bytes32 id) public view returns (Types.Owner memory) {
        return _owners[id];
    }
}
