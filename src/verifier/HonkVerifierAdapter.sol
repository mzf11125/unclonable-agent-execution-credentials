// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IVerifier} from "./IVerifier.sol";
import {IUnclonableCredential} from "../interfaces/IUnclonableCredential.sol";

/// @title HonkVerifierAdapter — Maps Capability to Circuit Public Inputs
/// @notice Wraps the bb-generated HonkVerifier and builds the public input
///         array from an IUnclonableCredential.Capability struct.
contract HonkVerifierAdapter is IVerifier {
    IVerifier public immutable verifier;

    constructor(address _verifier) {
        verifier = IVerifier(_verifier);
    }

    /// @notice Build the 8 public inputs expected by the Noir circuit
    /// @dev Order: [capabilityCommitment, agentId, homeChainId, homeDomainId,
    ///         capabilityIndex, actionCommitment, executor, expiry]
    function _buildPublicInputs(
        IUnclonableCredential.Capability calldata cap
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory inputs = new bytes32[](8);
        inputs[0] = cap.capabilityCommitment;
        inputs[1] = bytes32(uint256(cap.agentId));
        inputs[2] = bytes32(uint256(cap.homeChainId));
        inputs[3] = bytes32(uint256(cap.homeDomainId));
        inputs[4] = bytes32(uint256(cap.capabilityIndex));
        inputs[5] = cap.actionCommitment;
        inputs[6] = bytes32(uint256(uint160(cap.executor)));
        inputs[7] = bytes32(uint256(cap.expiry));
        return inputs;
    }

    /// @notice Verify a proof against a Capability.
    function verify(
        bytes calldata proof,
        IUnclonableCredential.Capability calldata cap
    ) external view returns (bool) {
        bytes32[] memory publicInputs = _buildPublicInputs(cap);
        return verifier.verify(proof, publicInputs);
    }

    /// @notice Verify a proof against raw public inputs.
    /// @dev Provided for compatibility with IVerifier.
    function verify(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external view returns (bool) {
        return verifier.verify(proof, publicInputs);
    }
}
