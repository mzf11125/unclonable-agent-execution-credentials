// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IUnclonableCredential} from "./interfaces/IUnclonableCredential.sol";
import {IVerifier} from "./verifier/IVerifier.sol";
import {DomainRegistry} from "./libraries/DomainRegistry.sol";
import {CapabilityCommitment} from "./libraries/CapabilityCommitment.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title UnclonableCredentialGuard — Normative Core Implementation
/// @notice Implements the seven consume checks from ERC-XXXX §4.1.
contract UnclonableCredentialGuard is IUnclonableCredential {
    using CapabilityCommitment for bytes32;

    mapping(bytes32 => bool) public consumed;
    IVerifier public immutable verifier;
    DomainRegistry public immutable domainRegistry;

    constructor(address _verifier, address _domainRegistry) {
        verifier = IVerifier(_verifier);
        domainRegistry = DomainRegistry(_domainRegistry);
    }

    /// @notice Rebuild public inputs in the exact order expected by the circuit
    ///         and the HonkVerifierAdapter.
    /// @dev Order: [capabilityCommitment, agentId, homeChainId, homeDomainId,
    ///         capabilityIndex, actionCommitment, executor, expiry]
    function _buildPublicInputs(
        Capability calldata cap
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

    /// @notice Enforce executor binding: direct submit or EIP-712 relayed signature.
    /// @dev Uses OpenZeppelin SignatureChecker so ERC-1271 accounts work.
    function _checkExecutor(Capability calldata cap) internal view returns (bool) {
        if (msg.sender == cap.executor) {
            return true;
        }
        // EIP-712 relayed signature by executor over the capability digest.
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(abi.encode(cap))
            )
        );
        return SignatureChecker.isValidSignatureNow(cap.executor, digest, "");
    }

    /// @notice Consume a capability exactly once.
    /// @dev The seven checks are executed in the order mandated by the spec.
    function consume(
        Capability calldata cap,
        bytes calldata proof
    ) external override returns (bytes32) {
        // 1. homeChainId == block.chainid
        require(cap.homeChainId == block.chainid, "UAC: wrong chain");

        // 2. homeDomainId is registered and not revoked
        require(domainRegistry.isActiveDomain(cap.homeDomainId), "UAC: domain invalid");

        // 3. block.timestamp <= expiry
        require(block.timestamp <= cap.expiry, "UAC: expired");

        // 4. msg.sender == executor, or valid EIP-712 signature by executor
        require(_checkExecutor(cap), "UAC: executor mismatch");

        // 5. !consumed[nullifier]
        require(!consumed[cap.nullifier], "UAC: already spent");

        // 6. verifier.verify(proof, publicInputs) passes
        bytes32[] memory publicInputs = _buildPublicInputs(cap);
        require(verifier.verify(proof, publicInputs), "UAC: invalid proof");

        // 7. Burn and emit
        consumed[cap.nullifier] = true;
        emit CapabilityConsumed(
            cap.nullifier,
            cap.agentId,
            cap.capabilityIndex,
            cap.executor,
            block.timestamp
        );
        return cap.nullifier;
    }

    /// @notice Query whether a nullifier has been burned.
    function isConsumed(bytes32 nullifier) external view override returns (bool) {
        return consumed[nullifier];
    }
}
