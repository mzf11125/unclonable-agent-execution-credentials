// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CoupledCredentialGuard} from "src/CoupledCredentialGuard.sol";
import {IUnclonableCredential} from "src/interfaces/IUnclonableCredential.sol";
import {MockVerifier} from "src/mocks/MockVerifier.sol";
import {DomainRegistry} from "src/libraries/DomainRegistry.sol";

/// @dev A trivial action target so "the action ran" is observable on chain.
contract MockTarget {
    uint256 public runs;

    function run() external {
        runs++;
    }
}

/// @notice The same adversarial vectors run against the coupled design. The action is a real
///         (target, callData) call whose commitment is keccak(target, callData), so the proof binds
///         the exact action the Guard performs.
contract CoupledCredentialGuardTest is Test {
    uint256 internal constant CHAIN_ID = 11155111;
    uint256 internal constant HOME_DOMAIN_ID = 1;
    bytes32 internal constant CAP_TAG = keccak256("ERC-8380/capability/v1");
    bytes32 internal constant NULL_TAG = keccak256("ERC-8380/nullifier/v1");

    DomainRegistry internal domainRegistry;
    MockVerifier internal verifier;
    CoupledCredentialGuard internal guard;
    MockTarget internal target;

    address internal orchestrator = address(0xA11CE);
    address internal agentExecutor = address(0xBEEF);
    bytes internal runData;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        domainRegistry = new DomainRegistry();
        domainRegistry.registerDomain(HOME_DOMAIN_ID, orchestrator);
        verifier = new MockVerifier();
        guard = new CoupledCredentialGuard(address(verifier), address(domainRegistry));
        target = new MockTarget();
        runData = abi.encodeCall(MockTarget.run, ());
    }

    function _cap(uint256 index, address t, bytes memory data)
        internal
        view
        returns (IUnclonableCredential.Capability memory)
    {
        return _capInDomain(index, HOME_DOMAIN_ID, t, data);
    }

    /// @dev Salt folds in the domain so domain A's and domain B's index-4 capabilities don't
    ///      collide by accident in the fixture. This is a test-helper choice, not a protocol rule.
    function _capInDomain(uint256 index, uint256 domainId, address t, bytes memory data)
        internal
        view
        returns (IUnclonableCredential.Capability memory)
    {
        bytes32 action = keccak256(abi.encode(t, data));
        bytes32 salt = keccak256(abi.encode("salt", domainId, index));
        bytes32 nullifier = keccak256(abi.encodePacked(NULL_TAG, salt));
        uint256 expiry = block.timestamp + 1 days;
        bytes32 commitment = keccak256(
            abi.encodePacked(
                CAP_TAG,
                salt,
                bytes32(uint256(1)),
                bytes32(uint256(CHAIN_ID)),
                bytes32(domainId),
                bytes32(index),
                action,
                bytes32(uint256(uint160(agentExecutor))),
                bytes32(expiry)
            )
        );
        return IUnclonableCredential.Capability({
            nullifier: nullifier,
            capabilityCommitment: commitment,
            agentId: 1,
            homeChainId: CHAIN_ID,
            homeDomainId: domainId,
            capabilityIndex: index,
            actionCommitment: action,
            executor: agentExecutor,
            expiry: expiry
        });
    }

    function _issue(IUnclonableCredential.Capability memory cap) internal {
        vm.prank(domainRegistry.orchestratorOf(cap.homeDomainId));
        guard.issue(cap.capabilityCommitment, cap.agentId, cap.homeDomainId, cap.capabilityIndex);
    }

    function _proof() internal pure returns (bytes memory) {
        return abi.encodePacked("proof");
    }

    /// @dev Distinct proof bytes per call, so locking one proof in a forgery test doesn't affect
    ///      other execute() calls in the same test that reuse the generic _proof().
    function _proof(uint256 tag) internal pure returns (bytes memory) {
        return abi.encodePacked("proof", tag);
    }

    /// @dev Mirrors the Guard's own _buildPublicInputs, so tests can lock a MockVerifier proof to
    ///      the exact public-input vector an honest execute() call would present.
    function _publicInputs(IUnclonableCredential.Capability memory cap)
        internal
        pure
        returns (bytes32[] memory inputs)
    {
        inputs = new bytes32[](9);
        inputs[0] = cap.capabilityCommitment;
        inputs[1] = bytes32(cap.agentId);
        inputs[2] = bytes32(cap.homeChainId);
        inputs[3] = bytes32(cap.homeDomainId);
        inputs[4] = bytes32(cap.capabilityIndex);
        inputs[5] = cap.actionCommitment;
        inputs[6] = bytes32(uint256(uint160(cap.executor)));
        inputs[7] = bytes32(cap.expiry);
        inputs[8] = cap.nullifier;
    }

    /// The grief burn is closed. A clone cannot consume the capability on an unissued action, so it
    /// cannot destroy it on an action of its choosing, and the honest action still runs.
    function test_Coupled_GriefOnUnissuedAction_Reverts() public {
        IUnclonableCredential.Capability memory honest = _cap(0, address(target), runData);
        _issue(honest);

        MockTarget other = new MockTarget();
        IUnclonableCredential.Capability memory grief = _cap(0, address(other), runData);
        vm.prank(agentExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(IUnclonableCredential.CommitmentNotIssued.selector, grief.capabilityCommitment)
        );
        guard.execute(grief, _proof(), address(other), runData);

        assertFalse(guard.isConsumed(honest.nullifier), "nothing was burned by the failed grief");
        vm.prank(agentExecutor);
        guard.execute(honest, _proof(), address(target), runData);
        assertEq(target.runs(), 1, "authorized action still runs");
    }

    /// Consumption cannot be separated from execution: a burned nullifier always means the action ran.
    function test_Coupled_BurnAlwaysExecutes() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);
        vm.prank(agentExecutor);
        guard.execute(cap, _proof(), address(target), runData);
        assertTrue(guard.isConsumed(cap.nullifier), "nullifier burned");
        assertEq(target.runs(), 1, "and the action executed in the same call");
    }

    /// Premature spend survives, but coupling changes what it costs. A clone triggering the
    /// authorized action early means the task is done once, not burned away undone.
    function test_Coupled_PrematureBecomesDoneNotDead() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);

        vm.prank(agentExecutor);
        guard.execute(cap, _proof(), address(target), runData);
        assertEq(target.runs(), 1, "authorized action executed exactly once");

        vm.prank(agentExecutor);
        vm.expectRevert(abi.encodeWithSelector(IUnclonableCredential.CredentialAlreadySpent.selector, cap.nullifier));
        guard.execute(cap, _proof(), address(target), runData);
        assertEq(target.runs(), 1, "still exactly once, done not dead");
    }

    /// A revert cannot emit, so observability is the burn event on the accepting path plus the
    /// named error on the rejecting one. `highestIssuedIndex` is what turns that error into a
    /// diagnosis: a collision at an index the orchestrator never issued is a clone, one at an index
    /// it did issue is its own reissue bug. Without it both look identical to an operator.
    function test_Coupled_CollisionIsClassifiable() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);

        vm.expectEmit(true, true, true, true, address(guard));
        emit IUnclonableCredential.NullifierBurned(cap.nullifier, cap.agentId, cap.capabilityIndex, cap.actionCommitment);
        vm.prank(agentExecutor);
        guard.execute(cap, _proof(), address(target), runData);

        // The collision lands on index 0, which the orchestrator did issue, so this is a reissue
        // bug on its own side rather than evidence of a clone.
        assertEq(guard.highestIssuedIndex(cap.agentId, cap.homeDomainId), 0);
        vm.prank(agentExecutor);
        vm.expectRevert(abi.encodeWithSelector(IUnclonableCredential.CredentialAlreadySpent.selector, cap.nullifier));
        guard.execute(cap, _proof(), address(target), runData);

        // An index beyond the highest issued cannot even reach the spent check, because the
        // commitment was never issued. That is the clone signature.
        IUnclonableCredential.Capability memory unissued = _cap(7, address(target), runData);
        assertGt(unissued.capabilityIndex, guard.highestIssuedIndex(unissued.agentId, unissued.homeDomainId));
        vm.prank(agentExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(IUnclonableCredential.CommitmentNotIssued.selector, unissued.capabilityCommitment)
        );
        guard.execute(unissued, _proof(), address(target), runData);
    }

    /// Recovery is the next index. A burned index stays burned; reauthorize at index + 1.
    function test_Coupled_Recovery_NextIndex() public {
        IUnclonableCredential.Capability memory first = _cap(0, address(target), runData);
        _issue(first);
        vm.prank(agentExecutor);
        guard.execute(first, _proof(), address(target), runData);

        IUnclonableCredential.Capability memory second = _cap(1, address(target), runData);
        _issue(second);
        vm.prank(agentExecutor);
        guard.execute(second, _proof(), address(target), runData);
        assertEq(target.runs(), 2, "recovered at the next index, never the burned one");
    }

    /// Bug fix: the nullifier is a constrained public input, not free calldata. A proof locked to
    /// the honest public-input vector must fail if the caller substitutes a different nullifier,
    /// closing the "clone mints itself a fresh nullifier" replay.
    function test_Coupled_ForgedNullifier_Reverts() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);
        bytes memory proof = _proof(1);
        verifier.lockProof(proof, _publicInputs(cap));

        IUnclonableCredential.Capability memory forged = cap;
        forged.nullifier = bytes32(uint256(cap.nullifier) ^ 1);

        vm.prank(agentExecutor);
        vm.expectRevert(CoupledCredentialGuard.BadProof.selector);
        guard.execute(forged, proof, address(target), runData);
    }

    /// Bug fix: executor is folded into the commitment preimage and is a constrained public input.
    /// A clone cannot self-assert a different executor against a proof locked to the issued one.
    function test_Coupled_ForgedExecutor_Reverts() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);
        bytes memory proof = _proof(2);
        verifier.lockProof(proof, _publicInputs(cap));

        address otherExecutor = address(0xC0FFEE);
        IUnclonableCredential.Capability memory forged = cap;
        forged.executor = otherExecutor;

        vm.prank(otherExecutor); // passes the msg.sender == cap.executor check
        vm.expectRevert(CoupledCredentialGuard.BadProof.selector);
        guard.execute(forged, proof, address(target), runData);
    }

    /// Bug fix: expiry is folded into the commitment preimage and is a constrained public input. A
    /// clone cannot self-assert a longer expiry against a proof locked to the issued one.
    function test_Coupled_ForgedExpiry_Reverts() public {
        IUnclonableCredential.Capability memory cap = _cap(0, address(target), runData);
        _issue(cap);
        bytes memory proof = _proof(3);
        verifier.lockProof(proof, _publicInputs(cap));

        IUnclonableCredential.Capability memory forged = cap;
        forged.expiry = cap.expiry + 365 days; // still > block.timestamp, passes the Expired check

        vm.prank(agentExecutor);
        vm.expectRevert(CoupledCredentialGuard.BadProof.selector);
        guard.execute(forged, proof, address(target), runData);
    }

    /// Bug fix: highestIssuedIndex is scoped per (agentId, homeDomainId). Domain A issuing 1..10
    /// must not make an unissued index 4 in domain B look like a reissue bug instead of a clone.
    function test_CollisionInASecondDomainIsMisclassified() public {
        uint256 domainB = 2;
        domainRegistry.registerDomain(domainB, orchestrator);

        for (uint256 i = 1; i <= 10; i++) {
            _issue(_cap(i, address(target), runData));
        }
        assertEq(guard.highestIssuedIndex(1, HOME_DOMAIN_ID), 10);
        assertEq(guard.highestIssuedIndex(1, domainB), 0, "domain B has issued nothing");

        IUnclonableCredential.Capability memory collision = _capInDomain(4, domainB, address(target), runData);
        assertGt(collision.capabilityIndex, guard.highestIssuedIndex(collision.agentId, domainB));

        vm.prank(agentExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(IUnclonableCredential.CommitmentNotIssued.selector, collision.capabilityCommitment)
        );
        guard.execute(collision, _proof(0), address(target), runData);
    }
}
