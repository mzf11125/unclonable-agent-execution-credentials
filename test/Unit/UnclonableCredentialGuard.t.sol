// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IUnclonableCredential} from "src/interfaces/IUnclonableCredential.sol";
import {UnclonableCredentialGuard} from "src/UnclonableCredentialGuard.sol";
import {MockVerifier} from "src/mocks/MockVerifier.sol";
import {DomainRegistry} from "src/libraries/DomainRegistry.sol";
import {CapabilityCommitment} from "src/libraries/CapabilityCommitment.sol";

contract UnclonableCredentialGuardTest is Test {
    uint256 constant HOME_DOMAIN_ID = 1;

    DomainRegistry domainRegistry;
    MockVerifier verifier;
    UnclonableCredentialGuard guard;

    function _buildCapability(
        uint256 agentId,
        uint256 capabilityIndex,
        uint256 expiry,
        bytes32 salt
    ) internal view returns (IUnclonableCredential.Capability memory) {
        uint256 chainId = block.chainid;
        bytes32 nullifier = keccak256(
            abi.encodePacked(keccak256("ERC-1953/nullifier/v1"), salt)
        );
        bytes32 actionCommitment = bytes32(uint256(0x42));
        bytes32 capabilityCommitment = keccak256(
            abi.encodePacked(
                keccak256("ERC-1953/capability/v1"),
                salt,
                bytes32(agentId),
                bytes32(chainId),
                bytes32(HOME_DOMAIN_ID),
                bytes32(capabilityIndex),
                actionCommitment,
                bytes32(uint256(uint160(address(this)))),
                bytes32(expiry)
            )
        );
        return IUnclonableCredential.Capability({
            nullifier: nullifier,
            capabilityCommitment: capabilityCommitment,
            agentId: agentId,
            homeChainId: chainId,
            homeDomainId: HOME_DOMAIN_ID,
            capabilityIndex: capabilityIndex,
            actionCommitment: actionCommitment,
            executor: address(this),
            expiry: expiry
        });
    }

    function _proof() internal pure returns (bytes memory) {
        return abi.encodePacked("proof");
    }

    /// @dev The salt is passed alongside the capability rather than read from it. It is a private
    ///      witness of the circuit and is deliberately not a struct field, so a test that wants to
    ///      recompute a commitment has to hold the salt itself, exactly as an issuer does.
    function _recomputeCommitment(
        IUnclonableCredential.Capability memory cap,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                keccak256("ERC-1953/capability/v1"),
                salt,
                bytes32(cap.agentId),
                bytes32(cap.homeChainId),
                bytes32(cap.homeDomainId),
                bytes32(cap.capabilityIndex),
                cap.actionCommitment,
                bytes32(uint256(uint160(cap.executor))),
                bytes32(cap.expiry)
            )
        );
    }

    function setUp() public {
        vm.chainId(11155111);
        domainRegistry = new DomainRegistry();
        domainRegistry.registerDomain(HOME_DOMAIN_ID, address(this));
        verifier = new MockVerifier();
        guard = new UnclonableCredentialGuard(address(verifier), address(domainRegistry));
    }

    function test_HappyPath() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        guard.consume(cap, _proof());
        assertTrue(guard.isConsumed(cap.nullifier));
    }

    function test_DoubleSpend_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        guard.consume(cap, _proof());
        vm.expectRevert("UAC: already spent");
        guard.consume(cap, _proof());
    }

    function test_CloneReplay_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        vm.prank(address(0xdead));
        vm.expectRevert("UAC: executor mismatch");
        guard.consume(cap, _proof());
    }

    function test_WrongChain_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        cap.homeChainId = 2;
        cap.capabilityCommitment = _recomputeCommitment(cap, bytes32(uint256(1)));
        vm.expectRevert("UAC: wrong chain");
        guard.consume(cap, _proof());
    }

    function test_Expired_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp - 1, bytes32(uint256(1)));
        vm.expectRevert("UAC: expired");
        guard.consume(cap, _proof());
    }

    function test_ExecutorMismatch_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        cap.executor = address(0xbeef);
        cap.capabilityCommitment = _recomputeCommitment(cap, bytes32(uint256(1)));
        vm.prank(address(0xdead));
        vm.expectRevert("UAC: executor mismatch");
        guard.consume(cap, _proof());
    }

    /// @dev The normative Guard has no relayed path. A relayer holding a valid capability and a
    ///      valid proof still cannot burn it, because check 4 is a strict sender equality. This
    ///      pins that behaviour so a future relayed extension has to be added deliberately rather
    ///      than by accident.
    function test_RelayedSubmit_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        vm.prank(address(0xbeef01));
        vm.expectRevert("UAC: executor mismatch");
        guard.consume(cap, _proof());
        assertFalse(guard.isConsumed(cap.nullifier));
    }

    function test_FrontRun_LiftedProof_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        vm.prank(address(0x999));
        vm.expectRevert("UAC: executor mismatch");
        guard.consume(cap, _proof());
    }

    function test_UnregisteredDomain_Reverts() public {
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, bytes32(uint256(1)));
        cap.homeDomainId = 2;
        cap.capabilityCommitment = _recomputeCommitment(cap, bytes32(uint256(1)));
        vm.expectRevert("UAC: domain invalid");
        guard.consume(cap, _proof());
    }

    /// @dev Parity between the library and the vectors written into the proposal. Both sides must
    ///      be built independently or the test proves nothing: the expectation below is the literal
    ///      from the spec, and the actual comes from CapabilityCommitment. That is what makes a
    ///      drifted domain tag a failing test rather than a silent production mismatch, since a
    ///      Guard and a circuit that disagree on a tag accept nothing.
    function test_CommitmentParity() public pure {
        bytes32 salt = bytes32(uint256(7));
        uint256 agentId = 5;
        uint256 capabilityIndex = 3;
        bytes32 actionCommitment = bytes32(uint256(99));
        address executor = address(0x000000000000000000000000000000000000dEaD);
        uint256 expiry = 2000000000;

        bytes32 expectedCommitment = keccak256(
            abi.encodePacked(
                keccak256("ERC-1953/capability/v1"),
                salt,
                bytes32(agentId),
                bytes32(uint256(11155111)),
                bytes32(HOME_DOMAIN_ID),
                bytes32(capabilityIndex),
                actionCommitment,
                bytes32(uint256(uint160(executor))),
                bytes32(expiry)
            )
        );
        assertEq(
            CapabilityCommitment.computeCapabilityCommitment(
                salt, agentId, 11155111, HOME_DOMAIN_ID, capabilityIndex, actionCommitment, executor, expiry
            ),
            expectedCommitment,
            "CAPABILITY_TAG or the commitment preimage drifted from the spec"
        );

        bytes32 expectedNullifier = keccak256(abi.encodePacked(keccak256("ERC-1953/nullifier/v1"), salt));
        assertEq(
            CapabilityCommitment.computeNullifier(salt),
            expectedNullifier,
            "NULLIFIER_TAG or the nullifier preimage drifted from the spec"
        );
    }

    /// @dev The fixtures build capabilities by hand rather than through the library, so pin them to
    ///      it too. Otherwise the fixtures and the library can drift apart and every other test in
    ///      this file keeps passing against the wrong tag.
    function test_FixtureParity() public view {
        bytes32 salt = bytes32(uint256(1));
        IUnclonableCredential.Capability memory cap = _buildCapability(1, 1, block.timestamp + 100, salt);
        assertEq(cap.nullifier, CapabilityCommitment.computeNullifier(salt), "fixture nullifier drifted");
        assertEq(
            cap.capabilityCommitment,
            CapabilityCommitment.computeCapabilityCommitment(
                salt, cap.agentId, cap.homeChainId, cap.homeDomainId, cap.capabilityIndex, cap.actionCommitment,
                cap.executor, cap.expiry
            ),
            "fixture commitment drifted"
        );
    }

    function test_Composition_Placeholder() public {
        assertTrue(true);
    }
}
