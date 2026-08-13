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
    bytes32 internal constant CAP_TAG = keccak256("ERC-XXXX/capability/v1");
    bytes32 internal constant NULL_TAG = keccak256("ERC-XXXX/nullifier/v1");

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
        domainRegistry.registerDomain(HOME_DOMAIN_ID);
        verifier = new MockVerifier();
        guard = new CoupledCredentialGuard(address(verifier), address(domainRegistry), orchestrator);
        target = new MockTarget();
        runData = abi.encodeCall(MockTarget.run, ());
    }

    function _cap(uint256 index, address t, bytes memory data)
        internal
        view
        returns (IUnclonableCredential.Capability memory)
    {
        bytes32 action = keccak256(abi.encode(t, data));
        bytes32 salt = keccak256(abi.encode("salt", index));
        bytes32 nullifier = keccak256(abi.encodePacked(NULL_TAG, salt));
        bytes32 commitment = keccak256(
            abi.encodePacked(
                CAP_TAG,
                salt,
                bytes32(uint256(1)),
                bytes32(uint256(CHAIN_ID)),
                bytes32(HOME_DOMAIN_ID),
                bytes32(index),
                action
            )
        );
        return IUnclonableCredential.Capability({
            salt: salt,
            nullifier: nullifier,
            capabilityCommitment: commitment,
            agentId: 1,
            homeChainId: CHAIN_ID,
            homeDomainId: HOME_DOMAIN_ID,
            capabilityIndex: index,
            actionCommitment: action,
            executor: agentExecutor,
            expiry: block.timestamp + 1 days
        });
    }

    function _issue(IUnclonableCredential.Capability memory cap) internal {
        vm.prank(orchestrator);
        guard.issue(cap.capabilityCommitment, cap.agentId, cap.capabilityIndex);
    }

    function _proof() internal pure returns (bytes memory) {
        return abi.encodePacked("proof");
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
            abi.encodeWithSelector(CoupledCredentialGuard.CommitmentNotIssued.selector, grief.capabilityCommitment)
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
        vm.expectRevert(abi.encodeWithSelector(CoupledCredentialGuard.CredentialAlreadySpent.selector, cap.nullifier));
        guard.execute(cap, _proof(), address(target), runData);
        assertEq(target.runs(), 1, "still exactly once, done not dead");
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
}
