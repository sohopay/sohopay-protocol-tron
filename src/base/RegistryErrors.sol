// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

// RegistryErrors — registry-local error surface (class 2 in docs/DECISIONS.md D-ERRTAX-1).
//
// Expected operator/backend registry failures that have no precise match in the frozen
// shared Types.sol. Declared at FILE LEVEL (a single definition each) and imported by both
// IdentityRegistry and MerchantRegistry, so the composing SohoSettlement can inherit both
// modules without "identifier already declared" collisions — which is what happens if each
// module declares its own copy. Keeps the frozen cross-contract surface (Types.sol)
// untouched while still giving backend/operators/auditors specific, decodable signals
// (same selector regardless of which registry reverts).
error AlreadyRegistered(bytes32 id);
error SignerInUse(address signer);
error InvalidStatusTransition(uint8 fromStatus, uint8 toStatus);
// Additive A2A (INV-A2A). Kept out of frozen Types.sol. Experimental: not in the prior audit.
error PayeeAgentNotActive(bytes32 agentId);
error PayeeReceiveUnset(bytes32 agentId);
error SelfPayment(bytes32 agentId);
