# ERC-1953: Unclonable Agent Execution Credentials

**Author:** Muhammad Zidan Fatonie (@mzf11125), Faisal Firdani (@zexoverz),
Maulana Asykari Muhammad (@WeissCurry), Venkata ramana Komari (@Venkat5599)

**Discussion:** [Ethereum Magicians thread 29274](https://ethereum-magicians.org/t/idea-draft-erc-unclonable-agent-execution-credentials-via-zero-knowledge-nullifiers/29274)

**Reference implementation:** this repository. The ERC submission copy is staged
in [`erc/`](./erc/).

## Status

Draft, submitted. Number 1953 assigned by the pull request number convention.

* Proposal: [ethereum/ERCs#1953](https://github.com/ethereum/ERCs/pull/1953),
  open as a draft.
* Submission copy in this repository: [`erc/erc-1953.md`](./erc/erc-1953.md).

The number is not final until the proposal merges. If an editor reassigns it,
rerun the rename in [`erc/PR.md`](./erc/PR.md) and resettle the two domain tags
below, because they carry the number.

## Update Log

* 2026-08-05: Initial idea draft opened for discussion on the forum thread.
* 2026-08-06: `chainId` removed from the nullifier preimage. Split into a chain
  independent nullifier and a chain bound capability commitment.
* 2026-08-11: Design green lit for implementation with issuance binding,
  two sided observability, and at most once with no ordering.
* 2026-08-16: [PR #1](https://github.com/mzf11125/unclonable-agent-execution-credentials/pull/1)
  merged. Adds `CoupledCredentialGuard` with mandatory issuance and coupled
  consumption plus execution, together with the adversarial vectors that close
  the grief burn.
* 2026-08-17: Coupling promoted from a recommended profile to the normative
  core. Salt removed from the on chain `Capability` struct. Relayed submission
  removed. Collision classification test added.
* 2026-08-17: [ethereum/ERCs#1953](https://github.com/ethereum/ERCs/pull/1953)
  opened as a draft. Domain separation tags settled from the `ERC-XXXX`
  placeholder to `ERC-1953` across the spec, the circuit notes, the Guards, and
  the fixtures.

## External Reviews

Thread 29274 in full. Everything below is folded into the draft.

* **babyblueviper1, post 2.** Unclonability and soundness are orthogonal
  properties a system needs both of, not substitutes. On mirroring, a nullifier
  registry is a spend problem where the answer must be unique rather than merely
  available, so redundancy without ordering is precisely what an attacker wants.
* **zexoverz, post 4.** The exactly once unit is per issuance, not per agent.
  Reuse of a spent salt is indistinguishable from a clone by design, so the
  orchestrator MUST NOT reissue a salt. Proposed
  `salt = HKDF(issuerSecret, agentId || homeDomainId || capabilityIndex)`.
* **cedricbrown, post 7.** A clone carries the same salt, the same `agentId`,
  and under executor binding the same executor key, so the Guard cannot rank the
  two by construction. A secondary time lock moves the race later without
  changing who wins it. A collision is the only on chain evidence a clone
  exists, and a bare revert makes a live compromise look identical to a
  scheduling bug.
* **zexoverz, post 8.** A revert cannot emit, so observability is the burn event
  on the accepting path plus a named error on the rejecting one.
* **helmymekaoui-web, post 10.** Introduces a fourth layer, an identity scoped
  cumulative bound. The draft bounds how many times a credential executes and
  says nothing about what consumption is worth in total. N clones of one agent
  should share one budget rather than multiplying it.
* **cedricbrown, posts 11 and 12.** The cheapest attack is not winning the race
  for the valuable action, it is spending the credential at all. Issuance
  binding narrows this rather than closing it. Whether the Guard checks the
  commitment against an issuance record is a security property, not an
  implementation detail. At most once bounds what an attacker can do with a
  credential and says nothing about what an attacker can do to one.
* **WeissCurry, post 13.** Separates issuer binding from execution coupling.
  Flags two implementation discrepancies, the nullifier preimage disagreement
  and the salt appearing in Solidity calldata while the circuit treats it as
  private. Proposes the explicit transition `issued[i]` then `burned[i]` then
  reissue at `i + 1`.
* **zexoverz, posts 14 and 15.** If a clone holds both salt and executor key, no
  interface check can distinguish them, which is a key management boundary. The
  fixable part is preventing a burn that leaves the intended execution
  unavailable, so consumption and execution belong in one call. Recovery means
  reissuance under a fresh salt rather than reviving a burned nullifier.

## Outstanding Issues

* [ ] 2026-08-05: **Cross chain nullifier synchronization.** A capability
  deliberately issued as spendable on either of two chains with no designated
  home needs real consensus on spentness. Current resolution is to bind each
  token to a home domain and require an explicit burn and reissue. Declared out
  of scope for a first draft rather than solved.

* [ ] 2026-08-05: **Proof generation latency.** Creating the ZK proof sits in the
  execution path, introducing a delay an attacker might exploit if they have
  already cloned the agent memory. Per post 7, a secondary time lock moves the
  race later without changing who wins it, so no mitigation is specified.

* [ ] 2026-08-11: **Aggregate consumption.** Exactly once per issuance is a count
  on one credential and does not bound what one identity consumes in total. Post
  10 proposes an identity scoped budget as a separate layer. Named as out of
  scope in the ERC, but nothing in this repository implements it.

* [ ] 2026-08-17: **Relayed submission.** The normative Guard requires
  `msg.sender == executor`, so an agent holding no gas cannot spend through a
  relayer. A proper EIP-712 path needs a signature argument on `execute` and a
  domain separator over the Guard address and `block.chainid`. The previous
  implementation reconstructed a malformed digest and passed an empty signature,
  which could never verify, and has been removed rather than left in place.
  Deferred until a concrete integrator asks for it.

* [ ] 2026-08-17: **Orchestrator is a single address.** `CoupledCredentialGuard`
  takes one immutable `orchestrator`. A domain with rotating or multi party
  issuance needs more, and the domain registry is the natural place for it.

## Summary

Agent authorization on Ethereum typically relies on function scoped boundaries
or static permissions. Both assume the credential holder is the party the
credential was issued to.

That assumption breaks in multi agent swarms. When building the LadingLogic
autonomous trade finance network we hit a security wall. When an orchestrator
delegates a high stakes task to a specialized off chain agent, it issues an
authorization credential, and a compromised agent can be cloned. A bad actor
copies the memory state and replays that authorization to drain funds or
duplicate actions. Nothing in a scoped permission distinguishes the original
agent from its clone, because both present the same valid credential for the
same permitted call.

The property needed is that an execution capability fundamentally breaks after
one use. By adapting the unconditional unclonable encryption result in
[arXiv 2607.21551](https://arxiv.org/abs/2607.21551), this draft brings quantum
inspired unclonability to classical EVM environments through zero-knowledge
nullifiers.

## How It Works

1. The orchestrator derives a per issuance salt, computes the capability
   commitment, and calls `issue` on chain. The capability itself travels to the
   agent off chain, bound to the agent identity and the salt.

2. The agent generates a zero-knowledge proof that it knows a salt opening the
   commitment. This proof generation forces the exposure of a nullifier derived
   from the salt. The salt itself never reaches the chain.

3. The Guard verifies the proof, checks the action being performed against the
   issued commitment, permanently logs the nullifier, and performs the action in
   the same call.

4. If a cloned credential attempts to execute, it produces the identical
   nullifier. The Guard sees the duplicate and rejects the transaction with
   `CredentialAlreadySpent`.

The standard defines only the capability envelope, the nullifier derivation, and
the verification interface. It does not define the proving system, the
capability transport, or the policy that decided the capability should be
issued.

## Three Choices Worth Surfacing Early

**Nullifiers derive from a hidden salt, not the transaction payload.** If the
nullifier were bound only to the payload, an identical legitimate subsequent
task would be blocked, which breaks any recurring agent action. Binding to a per
issuance salt ensures intentional duplicate tasks receive unique capability
tokens, while cloned tokens produce colliding nullifiers. The unit of exactly
once is the issuance.

**Unclonability moves from the storage layer to the execution layer.** The
original arXiv 2607.21551 result relies on quantum states. EVM environments are
classical and data is infinitely replicable, so no property of the credential at
rest can be made unclonable. This draft relocates the unclonable property to the
proof of execution, where the collision is detectable on chain.

**The burn is fused to the action.** A separable spend was specified first and
withdrawn. Under it a clone could burn a nullifier on any action and leave the
authorized work permanently undone, so exactly once held perfectly and the
deployment still lost. Issuance binding narrows that. Fusing closes what
remains.

## Scope of the Security Claim

This standard guarantees at most once execution with no ordering. It is not an
access control framework. The verifier learns that a specific single use
capability was consumed, and the Guard ensures no identical capability can ever
execute again.

It is not exactly once, because two holders of the same salt can race and the
Guard cannot rank them. It is not correct agent wins.

It hides nothing. A permitted action executes on a public chain and is public.
The claim is about how many times a credential can be spent, not about what the
credential authorizes or who can see it.

## Property Map

Adapted from post 13.

| Question | Answer | Source |
| --- | --- | --- |
| Was the action correctly authorized? | Outside this draft | posts 2, 3 |
| Can the same issuance execute twice? | No, at most once per issuance | post 7 |
| Which holder wins the race? | Unspecified | post 7 |
| Can a collision be observed? | Yes, burn event plus `CredentialAlreadySpent` | post 8 |
| Can a collision be classified? | Yes, against `highestIssuedIndex` | posts 7, 8 |
| How much can one identity consume in total? | Separate identity scoped budget layer | post 10 |
| Can a valid issuance be destroyed prematurely? | Bounded, not prevented. Mandatory issuance plus coupling means a landed burn always performs the authorized action | posts 11 to 15 |

## Relationship to Neighbouring Standards

| Standard | Layer | Relationship |
| --- | --- | --- |
| Function scoped delegation drafts | Boundary | Define what an agent may ever be authorized to touch. This proposal solves a different attack vector. Scoped delegation defines what an agent can reach, and this draft guarantees that a specific authorized payload executes at most once. |
| ERC-8354 Confidential Agent Policy Verdicts | Soundness | Defines how a particular authorization decision was reached, while keeping the ruleset confidential. A domain could plausibly use both, keeping the policy secret via ERC-8354 while ensuring the resulting credential cannot be replayed using this draft. Neither requires the other to function. |
| This draft | Consumption | Guarantees the resulting credential is spent at most once, and that a spend performs the issued action. |
| Identity scoped cumulative bound | Budget | Meters total spend per `agentId` so that N clones share one budget rather than multiplying it. Not defined here. |
| ERC-8004 | Identity | Supplies the agent identity the capability token binds to. |
| ERC-7579, ERC-6900 | Integration surface | The Guard operates as a pre execution hook or validation module. Dispatch must route through `execute`. |

**Unclonability and authorization soundness are orthogonal.** This standard
guarantees that a specific authorized payload executes at most once. It makes no
claim about whether that payload should have been authorized in the first place.
A replayed credential from a compromised agent and a correctly issued credential
encoding a genuinely bad decision are indistinguishable to the Guard, because
both present a valid, previously unseen nullifier. A deployment needs boundary,
soundness, consumption, and budget independently, and none of the four
substitutes for another.

## Normative Core

### Abstract

A minimal Guard primitive that verifies a zero-knowledge proof of a capability
and burns a nullifier at most once, as part of performing the issued action. A
capability encodes a single authorized execution event for an ERC-8004 agent.
The only secret is a salt, and the nullifier is `H(NULLIFIER_TAG, salt)`. Replay
by a clone is impossible because the same salt always maps to the same
nullifier, regardless of chain.

### Constants

```
NULLIFIER_TAG  = keccak256("ERC-1953/nullifier/v1")
CAPABILITY_TAG = keccak256("ERC-1953/capability/v1")
```

### Capability Struct

```solidity
struct Capability {
    bytes32 nullifier;            // public output, H(NULLIFIER_TAG, salt)
    bytes32 capabilityCommitment; // public input, binds salt to every field below
    uint256 agentId;              // ERC-8004 identity
    uint256 homeChainId;          // the one chain this capability spends on
    uint256 homeDomainId;         // issuing orchestrator domain
    uint256 capabilityIndex;      // monotonic per agentId and homeDomainId
    bytes32 actionCommitment;     // keccak256(abi.encode(target, callData))
    address executor;             // intended submitter
    uint256 expiry;               // unix seconds
}
```

> **Critical**: the salt is not a struct member. It is a private witness of the
> circuit only and MUST NOT appear in calldata, in an event, or in any other on
> chain artifact. A salt in calldata is public from the moment the transaction
> enters the mempool, which hands every observer the ability to grief burn the
> capability before it is mined. This closes the discrepancy raised in post 13.

### Salt Derivation

```
salt = HKDF(issuerSecret, agentId || homeDomainId || capabilityIndex)
```

`capabilityIndex` MUST be monotonically increasing per pair of `agentId` and
`homeDomainId`. An issuer MUST NOT reissue a spent salt, because reuse is
indistinguishable from a clone by construction. Any derivation yielding a
unique, unpredictable salt with at least 128 bits of entropy is acceptable. The
form above is recommended because it is stateless given the index.

### Derivation

```
nullifier            = H(NULLIFIER_TAG, salt)
capabilityCommitment = H(CAPABILITY_TAG, salt, agentId, homeChainId,
                         homeDomainId, capabilityIndex, actionCommitment)
```

> **Critical**: `chainId` MUST NOT be included in the nullifier preimage.
> Baking it in forks the nullifier per chain, so the same credential could be
> spent once on every chain. Chain binding is enforced by
> `homeChainId == block.chainid`.

`H` is `keccak256` over the `abi.encodePacked` concatenation, as implemented in
[`src/libraries/CapabilityCommitment.sol`](./src/libraries/CapabilityCommitment.sol).

The preimage is the tag and the salt alone. Posts 8 and 9 discussed
`H(salt, agentId, domainId)`. Both extra fields are already inputs to the salt
derivation and already bound by the capability commitment, so including them a
second time changes no security property and creates a second place for a
circuit and a Guard to disagree. This resolves the discrepancy raised in
post 13 in favour of the shorter preimage.

Open question 1 below is resolved in favour of keccak256 over Poseidon. Poseidon
is cheaper in circuit, but keccak256 makes Solidity side parity a direct
equality check, and a parity bug is paid by every integrator while proving cost
is paid once per capability by the agent.

### Public Inputs

The verifier receives eight public inputs in this exact order. Circuit and Guard
must agree, so the ordering is normative.

| Index | Value |
| --- | --- |
| 0 | `capabilityCommitment` |
| 1 | `agentId` |
| 2 | `homeChainId` |
| 3 | `homeDomainId` |
| 4 | `capabilityIndex` |
| 5 | `actionCommitment` |
| 6 | `executor` |
| 7 | `expiry` |

### Interface

See [`src/interfaces/IUnclonableCredential.sol`](./src/interfaces/IUnclonableCredential.sol).

```solidity
interface IUnclonableCredential {
    event CapabilityIssued(
        bytes32 indexed capabilityCommitment,
        uint256 indexed agentId,
        uint256 capabilityIndex
    );

    event NullifierBurned(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        uint256 capabilityIndex,
        bytes32 actionCommitment
    );

    error CredentialAlreadySpent(bytes32 nullifier);
    error CommitmentNotIssued(bytes32 capabilityCommitment);

    struct Capability { /* as above */ }

    function issue(
        bytes32 capabilityCommitment,
        uint256 agentId,
        uint256 capabilityIndex
    ) external;

    function execute(
        Capability calldata cap,
        bytes calldata proof,
        address target,
        bytes calldata callData
    ) external returns (bytes32 nullifier);

    function isConsumed(bytes32 nullifier) external view returns (bool);

    function highestIssuedIndex(uint256 agentId) external view returns (uint256);
}
```

### Issuance

`issue` is restricted to the issuing orchestrator. It records the commitment,
raises `highestIssuedIndex[agentId]` when the index exceeds it, and emits
`CapabilityIssued`.

Mandatory rather than optional. Because `capabilityCommitment` binds
`actionCommitment`, a Guard that accepts any internally consistent proof accepts
a capability for an action the orchestrator never authorized. Per post 12,
whether the Guard checks the commitment against an issuance record is a security
property and not an implementation detail.

### `execute` Checks (in order)

1. `homeChainId == block.chainid`
2. `homeDomainId` is registered and not revoked
3. `block.timestamp <= expiry`
4. `msg.sender == executor`
5. `!consumed[nullifier]`, else `CredentialAlreadySpent(nullifier)`
6. `issued[capabilityCommitment]`, else `CommitmentNotIssued(capabilityCommitment)`
7. `keccak256(abi.encode(target, callData)) == actionCommitment`
8. `verifier.verify(proof, publicInputs)` passes

Then set `consumed[nullifier] = true`, emit `NullifierBurned`, call
`target` with `callData`, and revert everything if the action reverts.

Cheap public checks precede proof verification so that a caller cannot force an
expensive verification with a capability that already fails on a public field.

No path may mark a nullifier consumed without performing the committed action,
and no path may clear a consumed nullifier.

### Observability

A rejecting path reverts and therefore cannot emit. Observability is two sided
and both sides are required.

* The first and only successful spend emits `NullifierBurned`.
* Every subsequent attempt reverts with `CredentialAlreadySpent`.

`highestIssuedIndex` turns that error into a diagnosis. A collision at an index
the orchestrator never issued indicates a clone. One at an index it did issue
indicates a reissue bug on the orchestrator side. Exercised by
`test_Coupled_CollisionIsClassifiable`.

### Recovery

A burned nullifier stays burned. The transition for an index is `issued`, then
`burned`, then reissue at `index + 1` under a fresh salt. Reviving a burned
nullifier is forbidden. When to reissue is orchestrator policy.

## Security Considerations

### Unclonability and Soundness Are Orthogonal

A replayed stolen credential and a correctly issued credential encoding a bad
decision are indistinguishable to the Guard. A deployment needs a boundary, a
soundness argument, this consumption guarantee, and a budget, independently.

### At Most Once, With No Ordering

A clone holding the agent memory holds the salt, and under executor binding the
same executor key, so the Guard cannot rank the two by construction. Both can
race, and the standard guarantees only that one lands, not which. A secondary
time lock moves the race later without changing who wins it. Deployments that
need the honest agent to win must keep the salt outside cloneable memory.

### Salt Secrecy Is a Liveness Property

A publicly computable nullifier would let anyone burn a capability before the
honest agent spends it. This is why the salt is excluded from the struct. A
leaked salt does not let an attacker perform an unauthorized action, because the
action is fixed by `actionCommitment` and by the issuance record, but it does
let an attacker consume the capability early.

### What an Attacker Can Do To a Credential

At most once bounds what an attacker can do with a credential. It says nothing
on its own about what an attacker can do to one. The cheapest attack for a clone
is not winning the race for the valuable action, it is spending the credential
at all.

The separable form is exhibited by
[`test/adversarial/GriefBurn.t.sol`](./test/adversarial/GriefBurn.t.sol) running
against the non-normative
[`src/UnclonableCredentialGuard.sol`](./src/UnclonableCredentialGuard.sol). A
clone burns the capability on a null action, nothing is replayed, the at most
once guarantee holds perfectly, and the deployment loses.
[`test/adversarial/Coupled.t.sol`](./test/adversarial/Coupled.t.sol) shows the
normative Guard bounding it: an unissued action cannot burn, and a burn that
does land performs the authorized action.

### Aggregate Consumption Is Not Bounded

A compromised agent that keeps receiving fresh capabilities spends each of them
once, legitimately, and drains value without ever triggering a collision.
Deployments handling value should meter cumulative spend per `agentId` in a
separate layer.

### Home Domain Required

A nullifier registry is a spend problem, where the answer must be unique rather
than merely available, so redundancy without ordering is precisely what an
attacker wants. First draft requires a home domain. A nullifier burned on one
chain must not be treated as evidence of spentness on another unless a mirroring
scheme with its own ordering guarantee is in place.

### Verifier Trust

The Guard delegates soundness to its verifier. A verifier that accepts an
invalid proof defeats every guarantee here. The verifier address must be
immutable, or governed at least as strongly as the value the capabilities
authorize. `src/mocks/MockVerifier.sol` exists for unit isolation and must never
be deployed to a production network.

## Open Questions

1. ~~Hash choice inside the circuit.~~ Resolved 2026-08-17 in favour of
   keccak256. Rationale is under Derivation above.
2. ~~Should `capabilityIndex` be enforced monotonic on chain?~~ Resolved
   2026-08-17 as issuer-side discipline. The Guard cannot distinguish legitimate
   out of order issuance from a replay attempt, and rejecting the former would
   break concurrent issuance. `highestIssuedIndex` records the ceiling so a
   collision can be classified after the fact.
3. Does the Guard need its own domain registry, or should it read the CAPV
   `PolicyDomainRegistry`?
4. Is `expiry` sufficient revocation, or does the orchestrator need an explicit
   `revoke(capabilityCommitment)` that unissues before a spend lands?

## Feedback Wanted

1. Are there edge cases in the nullifier derivation path that could
   unintentionally brick legitimate recurring agent actions?

2. Does this unclonable approach cleanly stack with existing capability
   architectures, or does it introduce friction for developers? In particular,
   does routing dispatch through `execute` conflict with how ERC-7579 and
   ERC-6900 modules expect to return a verdict and let the account dispatch?

3. For anyone working on cross chain agent execution, how would you handle
   nullifier registry mirroring, particularly where a capability is deliberately
   issued without a designated home domain?

4. Is binding unclonability to the proof of execution rather than the credential
   itself the right relocation, or is there a construction that gets closer to
   the original quantum property in a classical setting?

## License

CC0-1.0. See [LICENSE](./LICENSE).
