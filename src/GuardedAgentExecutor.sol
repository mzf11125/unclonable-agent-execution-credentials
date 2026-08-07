// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IUnclonableCredential} from "./interfaces/IUnclonableCredential.sol";
import {UnclonableCredentialGuard} from "./UnclonableCredentialGuard.sol";
import {DomainRegistry} from "./libraries/DomainRegistry.sol";
import {IVerifier} from "./verifier/IVerifier.sol";

/// @title GuardedAgentExecutor — Example Consumer
/// @notice Demonstrates how to integrate UnclonableCredentialGuard into
///         a workflow. Not audited. For reference only.
contract GuardedAgentExecutor {
    UnclonableCredentialGuard public immutable guard;

    event ActionExecuted(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        bytes32 actionCommitment
    );

    constructor(address _guard) {
        guard = UnclonableCredentialGuard(_guard);
    }

    /// @notice Execute an action under an unclonable credential.
    /// @dev The caller must supply a Capability whose actionCommitment matches
    ///      the intended action. The Guard never sees the action parameters.
    function execute(
        IUnclonableCredential.Capability calldata cap,
        bytes calldata proof,
        bytes32 expectedActionCommitment
    ) external returns (bytes32) {
        require(cap.actionCommitment == expectedActionCommitment, "UAC: action mismatch");
        bytes32 nullifier = guard.consume(cap, proof);
        emit ActionExecuted(nullifier, cap.agentId, cap.actionCommitment);
        return nullifier;
    }
}
