// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title IUnclonableCredential — Unclonable Agent Execution Credentials
/// @notice Normative interface for ERC-XXXX. Defines the Capability struct
///         and the consume / isConsumed primitives.
interface IUnclonableCredential {
    /// @notice Capability metadata bound to a single agent action.
    /// @dev The salt is the only secret. All other fields are public inputs.
    struct Capability {
        bytes32 salt;               // private witness
        bytes32 nullifier;          // public output: H(NULLIFIER_TAG, salt)
        bytes32 capabilityCommitment; // public input: binds salt to all other fields
        uint256 agentId;            // ERC-8004 identity
        uint256 homeChainId;        // the one chain this capability spends on
        uint256 homeDomainId;       // issuing orchestrator domain
        uint256 capabilityIndex;    // monotonic per (agentId, homeDomainId)
        bytes32 actionCommitment;   // canonical action hash, CAPV PolicyAction shape
        address executor;           // intended submitter
        uint256 expiry;             // unix seconds
    }

    /// @notice Consume a capability exactly once.
    /// @dev Reverts if any of the seven checks in the normative spec fail.
    /// @return nullifier The burned nullifier.
    function consume(
        Capability calldata cap,
        bytes calldata proof
    ) external returns (bytes32 nullifier);

    /// @notice Query whether a nullifier has been burned.
    function isConsumed(bytes32 nullifier) external view returns (bool);

    /// @notice Emitted when a capability is successfully consumed.
    /// @dev Indexed topics: nullifier, agentId, capabilityIndex. executor is
    ///      included in the event data but not indexed (Solidity limit: 3 indexed).
    event CapabilityConsumed(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        uint256 indexed capabilityIndex,
        address executor,
        uint256 timestamp
    );
}
