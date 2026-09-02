// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IVerifier} from "../verifier/IVerifier.sol";

/// @title MockVerifier — Always-True Verifier for Unit Isolation, With Optional Locking
/// @notice Used only in tests. MUST NOT be used in production.
contract MockVerifier is IVerifier {
    /// @dev proofHash => locked. A locked proof only verifies against the exact publicInputs it
    ///      was locked to, simulating a real verifier's constraint on the public input vector. An
    ///      unlocked proof (the default) verifies against anything, preserving the always-true
    ///      behaviour tests that don't care about constraint simulation rely on.
    mapping(bytes32 => bool) public locked;
    mapping(bytes32 => bytes32) public lockedInputsHash;

    /// @notice Simulate "this proof is only valid for this exact public-input vector." Test-only.
    ///         A real verifier enforces this cryptographically; this lets adversarial tests
    ///         exercise the Guard's response to a public-input mismatch without a real prover.
    function lockProof(bytes calldata proof, bytes32[] calldata publicInputs) external {
        bytes32 proofHash = keccak256(proof);
        locked[proofHash] = true;
        lockedInputsHash[proofHash] = keccak256(abi.encode(publicInputs));
    }

    function verify(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external view override returns (bool) {
        bytes32 proofHash = keccak256(proof);
        if (!locked[proofHash]) return true;
        return lockedInputsHash[proofHash] == keccak256(abi.encode(publicInputs));
    }
}
