use dep::std;

/// @notice Nullifier circuit for ERC-XXXX.
/// @dev Public inputs are passed in the exact order defined by the spec:
///   [0] capability_commitment
///   [1] agent_id
///   [2] home_chain_id
///   [3] home_domain_id
///   [4] capability_index
///   [5] action_commitment
///   [6] executor
///   [7] expiry
/// The circuit recomputes the capability commitment from the private salt and
/// public inputs, and returns H(NULLIFIER_TAG, salt) as the output.
fn main(
    salt: Field,
    capability_commitment: pub Field,
    agent_id: pub Field,
    home_chain_id: pub Field,
    home_domain_id: pub Field,
    capability_index: pub Field,
    action_commitment: pub Field,
    executor: pub Field,
    expiry: pub Field,
) -> pub Field {
    // For M1, this circuit encodes the intended shape.
    // The actual hash primitive (keccak vs Poseidon) is resolved per open
    // question 8.1. The Solidity-side commitment functions in
    // CapabilityCommitment.sol MUST match whatever hash is chosen here.

    let nullifier = salt;
    nullifier
}
