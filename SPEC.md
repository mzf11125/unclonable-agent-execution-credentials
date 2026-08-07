# ERC-XXXX: Unclonable Agent Execution Credentials

## Status
Draft — pre-implementation. No ERC number assigned.

## Abstract
A minimal Guard primitive that verates a zero-knowledge proof of a capability
and burns a nullifier exactly once. A capability encodes a single authorized
execution event for an ERC-8004 agent. The only secret is a salt; the nullifier
is `H(NULLIFIER_TAG, salt)`. Replay by a clone is impossible because the clone
cannot compute a new nullifier for a spent salt, and the same salt always maps
to the same nullifier regardless of chain.

## Normative Core

### Constants

```
NULLIFIER_TAG  = keccak256("ERC-XXXX/nullifier/v1")
CAPABILITY_TAG = keccak256("ERC-XXXX/capability/v1")
```

### Capability Struct

```solidity
struct Capability {
    bytes32 salt;
    bytes32 nullifier;
    bytes32 capabilityCommitment;
    uint256 agentId;
    uint256 homeChainId;
    uint256 homeDomainId;
    uint256 capabilityIndex;
    bytes32 actionCommitment;
    address executor;
    uint256 expiry;
}
```

### Derivation

```
nullifier            = H(NULLIFIER_TAG, salt)
capabilityCommitment = H(CAPABILITY_TAG, salt, agentId, homeChainId,
                         homeDomainId, capabilityIndex, actionCommitment)
```

> **Critical**: `chainId` MUST NOT be included in the nullifier preimage.
> Chain binding is enforced by `homeChainId == block.chainid`.

## Interface

```solidity
interface IUnclonableCredential {
    struct Capability { ... }
    function consume(Capability calldata cap, bytes calldata proof)
        external returns (bytes32 nullifier);
    function isConsumed(bytes32 nullifier) external view returns (bool);
    event CapabilityConsumed(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        uint256 indexed capabilityIndex,
        address indexed executor,
        uint256 timestamp
    );
}
```

## `consume` Checks (in order)

1. `homeChainId == block.chainid`
2. `homeDomainId` is registered and not revoked
3. `block.timestamp <= expiry`
4. `msg.sender == executor`, or valid EIP-712 signature by `executor`
5. `!consumed[nullifier]`
6. `verifier.verify(proof, publicInputs)` passes
7. Set `consumed[nullifier] = true`, emit, return

## Security Considerations

### Home Domain Required
A capability spendable on either of two chains with no designated home needs
real consensus on spentness. First draft requires a home domain.

### At-Most-Once, Not Correct-Agent-Wins
A clone holding the agent's memory holds the salt. Both can race, and the
standard guarantees only that one lands, not which.

### Salt Secrecy Is a Liveness Property
A publicly computable nullifier would let anyone burn a capability before the
honest agent spends it.

### Unclonability and Soundness Are Orthogonal
A replayed stolen credential and a correctly issued credential encoding a bad
decision are indistinguishable to the Guard.

## Open Questions

1. Hash choice inside the circuit. Poseidon is cheaper in-circuit but keccak
   keeps Solidity-side parity trivial.
2. Should `capabilityIndex` be enforced monotonic on chain, or left as
   issuer-side discipline?
3. Does the Guard need its own domain registry, or should it read the CAPV
   `PolicyDomainRegistry`?
4. Is `expiry` sufficient revocation, or does the orchestrator need an explicit
   `revoke(nullifier)`?

## License
CC0-1.0. See [LICENSE](./LICENSE).
