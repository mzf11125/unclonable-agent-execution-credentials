// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IUnclonableCredential} from "src/interfaces/IUnclonableCredential.sol";
import {UnclonableCredentialGuard} from "src/UnclonableCredentialGuard.sol";
import {MockVerifier} from "src/mocks/MockVerifier.sol";
import {DomainRegistry} from "src/libraries/DomainRegistry.sol";

/// @notice Shared fixtures for ERC-XXXX tests.
contract Fixtures is Test {
    uint256 constant CHAIN_ID = 11155111; // Sepolia
    uint256 constant HOME_DOMAIN_ID = 1;

    DomainRegistry public domainRegistry;
    MockVerifier public verifier;
    UnclonableCredentialGuard public guard;

    function _buildCapability(
        uint256 agentId,
        uint256 capabilityIndex,
        uint256 expiry,
        bytes32 salt
    ) internal view returns (IUnclonableCredential.Capability memory) {
        bytes32 nullifier = keccak256(
            abi.encodePacked(keccak256("ERC-XXXX/nullifier/v1"), salt)
        );
        bytes32 actionCommitment = bytes32(uint256(0x42));
        bytes32 capabilityCommitment = keccak256(
            abi.encodePacked(
                keccak256("ERC-XXXX/capability/v1"),
                salt,
                bytes32(agentId),
                bytes32(uint256(CHAIN_ID)),
                bytes32(HOME_DOMAIN_ID),
                bytes32(capabilityIndex),
                actionCommitment
            )
        );
        return IUnclonableCredential.Capability({
            salt: salt,
            nullifier: nullifier,
            capabilityCommitment: capabilityCommitment,
            agentId: agentId,
            homeChainId: CHAIN_ID,
            homeDomainId: HOME_DOMAIN_ID,
            capabilityIndex: capabilityIndex,
            actionCommitment: actionCommitment,
            executor: address(this),
            expiry: expiry
        });
    }

    function _buildCapabilityFor(
        address executor,
        uint256 agentId,
        uint256 capabilityIndex,
        uint256 expiry,
        bytes32 salt
    ) internal view returns (IUnclonableCredential.Capability memory) {
        IUnclonableCredential.Capability memory cap = _buildCapability(agentId, capabilityIndex, expiry, salt);
        cap.executor = executor;
        return cap;
    }

    function _proof() internal pure returns (bytes memory) {
        return abi.encodePacked("proof");
    }

    function _setUp() internal {
        domainRegistry = new DomainRegistry();
        domainRegistry.registerDomain(HOME_DOMAIN_ID);
        verifier = new MockVerifier();
        guard = new UnclonableCredentialGuard(address(verifier), address(domainRegistry));
    }
}
