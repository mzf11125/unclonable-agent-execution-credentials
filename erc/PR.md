# Submission notes for ethereum/ERCs

Everything below is for the human opening the PR. Do not commit this file to the
ERCs fork.

## Title

```
Add ERC: Unclonable Agent Execution Credentials
```

## Body

```markdown
This proposal defines a single use capability token for delegated agent execution. An orchestrator issues a capability bound to an agent identity and a per issuance secret salt. Spending it requires a zero-knowledge proof, which forces a nullifier derived from that salt into the open, and the Guard burns the nullifier as part of performing the authorized action. A cloned agent holds the same salt, produces the same nullifier, and is rejected.

The idea was discussed on Ethereum Magicians before this PR was opened:
https://ethereum-magicians.org/t/idea-draft-erc-unclonable-agent-execution-credentials-via-zero-knowledge-nullifiers/29274

That thread ran for two weeks and changed the design three times. The substantive points and where each landed:

- Unclonability and authorization soundness are orthogonal (https://ethereum-magicians.org/t/idea-draft-erc-unclonable-agent-execution-credentials-via-zero-knowledge-nullifiers/29274/2). This is now the leading subsection of Security Considerations rather than a footnote. The proposal states plainly that it supplies one of several independent layers and that adopting it alone does not make an agent safe.
- `chainId` must not be in the nullifier preimage, or the nullifier forks per chain and the credential is spendable once on each. Chain binding is now an acceptance check on `homeChainId` instead.
- A separable spend primitive lets anyone satisfying the executor check burn a capability without performing the work, so exactly once holds and the deployment still loses. Issuance is now mandatory and the burn is fused to the authorized call. This was the largest change and it came directly from adversarial test vectors contributed on the thread.
- A revert cannot emit, so observability is a burn event on the accepting path plus a named error on the rejecting one, with `highestIssuedIndex` to classify a collision as a clone versus an issuer reissue bug.
- The security claim is stated as at most once with no ordering, not exactly once. Two holders of the same salt race and the Guard cannot rank them.
- Aggregate spend per identity is named as a separate layer and explicitly out of scope.

The reference implementation lives at https://github.com/mzf11125/unclonable-agent-execution-credentials and the Solidity sources are also vendored into `assets/erc-1953/`, so the proposal body carries no external links. Nineteen Foundry tests cover the cases in the Test Cases section, including the adversarial vectors from the thread.

Known open questions, stated rather than hidden:

1. Cross chain nullifier mirroring. A capability deliberately issued as spendable on either of two chains with no designated home needs real consensus on spentness. The draft requires a home domain and declares the other case out of scope rather than solving it.
2. Proof generation latency. Proving sits in the execution path, and an attacker holding cloned memory can start proving at the same moment. No mitigation is specified, because a time lock moves the race later without changing who wins it.
3. Relayed submission. The Guard requires `msg.sender == executor`, so an agent holding no gas cannot spend through a relayer. Adding an EIP-712 path needs a signature argument on `execute`, which changes the interface, so it is deferred.

All authors listed in the preamble have consented to CC0 licensing and to being named.
```

## The number

The `preamble-file-name` lint requires the filename to match the `eip` field, and
the `ethereum/ERCs` convention is that the ERC number is the pull request number.
That number does not exist until the PR is opened, so the files here are staged
on a prediction.

At the time of staging the highest number `ethereum/ERCs` had handed out was
1952, dated 2026-08-15, so the next pull request lands on **1953**. That is what
`erc/erc-1953.md` and `erc/assets/erc-1953/` use.

The prediction is only correct if nobody else opens a pull request or an issue on
that repository first. Check the PR URL the moment it is opened, and if the
number differs, run the rename below.

```bash
# from the root of the ERCs fork, with N set to the real PR number
N=1953
git mv ERCS/erc-1953.md "ERCS/erc-$N.md"
git mv assets/erc-1953 "assets/erc-$N"
sed -i "s/erc-1953/erc-$N/g; s/^eip: 1953$/eip: $N/" "ERCS/erc-$N.md"
grep -n "1953" "ERCS/erc-$N.md"   # must print nothing
```

## Submission flow

1. Fork `ethereum/ERCs` and branch. Copy `erc/erc-1953.md` to `ERCS/erc-1953.md`
   and `erc/assets/erc-1953/` to `assets/erc-1953/`. Open the PR as a **draft**.
2. Confirm the number, applying the rename above if it is not 1953, then run the
   pre-push checks, force push, and mark the PR ready for review.

The two domain tag constants still read `ERC-XXXX`. That is deliberate. The
number is not final until the proposal merges, and baking a predicted number into
a cryptographic domain separator now means changing a constant twice. Replace
`ERC-XXXX` with the assigned number in the proposal, in this repository's
`src/libraries/CapabilityCommitment.sol`, in the vendored assets copy, and in the
test fixtures once the number is settled, then rerun `forge test`.
`test_CommitmentParity` is the test that catches a mismatch.

## Pre-push checks

Run these from inside the ERCs fork before marking the PR ready. They are the
same jobs `.github/workflows/ci.yml` runs.

```bash
# eipw needs the merged corpus so cross reference lints resolve
git clone --depth 1 https://github.com/ethereum/EIPs /tmp/EIPs
cp -p /tmp/EIPs/EIPS/eip-*.md ERCS/
for f in ERCS/erc-*.md; do cp -p "$f" "ERCS/eip-${f#ERCS/erc-}"; done
eipw --config config/eipw.toml "ERCS/erc-$N.md"

markdownlint-cli2 --config config/.markdownlint.yaml "ERCS/erc-$N.md"
codespell -I config/.codespell-whitelist "ERCS/erc-$N.md"
```

Then `git checkout ERCS` to drop the copied corpus before pushing.

## Lint constraints already satisfied

Verified against `config/eipw.toml` in `ethereum/ERCs` at master.

* Title is 38 characters, has no colon, and contains no form of the word
  standard.
* Description is 108 characters, within the 2 to 140 bound, with no colon and no
  form of the word standard.
* `discussions-to` matches `^https://ethereum-magicians.org/t/[^/]+/[0-9]+$`.
  The review comment link ending `/2` would fail this, which is why it appears
  only in the PR body.
* All proposal links use `./eip-N.md`, never `./erc-N.md`, which is the form the
  merged corpus resolves. Every first mention of a proposal is a link.
* No external links in the body. The arXiv paper is cited with a `csl-json`
  block carrying a DOI and URL, and the reference implementation is vendored
  into assets.
* Section order is Abstract, Motivation, Specification, Rationale, Backwards
  Compatibility, Test Cases, Reference Implementation, Security Considerations,
  Copyright.
* Copyright text is the exact mandated sentence.
* `requires: 6900, 7579, 8004` are all Draft, which a Draft proposal may require.
* No smart quotes anywhere.

One residual risk. `ERC-XXXX` appears inside code fences in the Constants
section. The `markdown-no-backticks` lint forbids a proposal reference in
backticks, but `ERC-XXXX` has no digits so it cannot match the pattern, and
merged proposals including ERC-1155 and ERC-721 do carry proposal references
inside code fences. Once the tag is replaced with the assigned number it does
contain digits, so recheck at that point. If eipw flags it, change the tag to
`unclonable-credential/nullifier/v1` and update
`src/libraries/CapabilityCommitment.sol` and the fixtures to match.
