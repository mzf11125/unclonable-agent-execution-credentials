// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {Fixtures} from "../helpers/Fixtures.sol";
import {IUnclonableCredential} from "src/interfaces/IUnclonableCredential.sol";

/// @notice Adversarial vectors from ethereum-magicians.org/t/29274, adapted to the Capability
///         struct. These run against the current normative Guard and show the grief burn is open:
///         `consume` requires no issuance and the nullifier is action-independent, so a clone that
///         holds the salt can burn the capability on an action of its choosing.
contract AdversarialGriefBurnTest is Fixtures {
    bytes32 internal constant CAP_TAG = keccak256("ERC-1953/capability/v1");
    bytes32 internal constant NULL_TAG = keccak256("ERC-1953/nullifier/v1");

    bytes32 internal constant REAL_ACTION = bytes32(uint256(0x42));
    bytes32 internal constant NULL_ACTION = bytes32(0);

    function setUp() public {
        _setUp();
        vm.chainId(CHAIN_ID);
    }

    /// @dev A clone shares the agent's memory, so it holds the salt for the index.
    function _cap(uint256 index, bytes32 action) internal view returns (IUnclonableCredential.Capability memory) {
        bytes32 salt = keccak256(abi.encode("salt", index));
        bytes32 nullifier = keccak256(abi.encodePacked(NULL_TAG, salt));
        uint256 expiry = block.timestamp + 1 days;
        bytes32 commitment = keccak256(
            abi.encodePacked(
                CAP_TAG,
                salt,
                bytes32(uint256(1)),
                bytes32(uint256(CHAIN_ID)),
                bytes32(HOME_DOMAIN_ID),
                bytes32(index),
                action,
                bytes32(uint256(uint160(address(this)))),
                bytes32(expiry)
            )
        );
        return IUnclonableCredential.Capability({
            nullifier: nullifier,
            capabilityCommitment: commitment,
            agentId: 1,
            homeChainId: CHAIN_ID,
            homeDomainId: HOME_DOMAIN_ID,
            capabilityIndex: index,
            actionCommitment: action,
            executor: address(this),
            expiry: expiry
        });
    }

    /// The clone spends the credential on a null action. The honest agent's real task can then never
    /// run. Nothing was replayed and the at-most-once guarantee held perfectly. The deployment lost.
    function test_GriefBurn_OnNullAction_KillsTheCapability() public {
        IUnclonableCredential.Capability memory grief = _cap(0, NULL_ACTION);
        guard.consume(grief, _proof());
        assertTrue(guard.isConsumed(grief.nullifier), "clone burned the nullifier");

        IUnclonableCredential.Capability memory honest = _cap(0, REAL_ACTION);
        assertEq(honest.nullifier, grief.nullifier, "same salt, same nullifier, different action");
        vm.expectRevert(bytes("UAC: already spent"));
        guard.consume(honest, _proof());
    }

    /// Recovery has no stated path. Once an index is burned it stays burned, so the only way back is
    /// the next index. This is the rule the spec is missing, written down.
    function test_RecoveryAfterGriefBurn_RequiresNextIndex() public {
        guard.consume(_cap(0, NULL_ACTION), _proof());

        IUnclonableCredential.Capability memory retry = _cap(0, REAL_ACTION);
        vm.expectRevert(bytes("UAC: already spent"));
        guard.consume(retry, _proof());

        IUnclonableCredential.Capability memory reissued = _cap(1, REAL_ACTION);
        guard.consume(reissued, _proof());
        assertTrue(guard.isConsumed(reissued.nullifier), "capability replaced at the next index, never the burned one");
    }

    /// At most once with no ordering. Two identical spends, exactly one lands, and the Guard cannot
    /// rank a clone against the original: same salt, same agentId, same executor.
    function test_Race_ExactlyOneLands_OrderUnspecified() public {
        IUnclonableCredential.Capability memory cap = _cap(0, REAL_ACTION);
        uint256 landed;
        try guard.consume(cap, _proof()) {
            landed++;
        } catch {}
        try guard.consume(cap, _proof()) {
            landed++;
        } catch {}
        assertEq(landed, 1, "exactly one execution, ordering not determined by the Guard");
    }
}
