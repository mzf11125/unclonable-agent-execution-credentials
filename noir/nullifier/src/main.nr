use dep::std;

mod hash;

/// @notice Nullifier circuit for ERC-1953.
/// @dev Public inputs are passed in the exact order defined by the spec:
///   [0] capability_commitment
///   [1] agent_id
///   [2] home_chain_id
///   [3] home_domain_id
///   [4] capability_index
///   [5] action_commitment
///   [6] executor
///   [7] expiry
///   [8] nullifier
/// The circuit constrains both capability_commitment and nullifier against the private salt.
/// Neither is a circuit output: in Groth16/PLONK-style systems a public output is implemented
/// as an entry in the public input vector, and the Guard's only way to check a value is to
/// compare that entry against calldata. Returning nullifier as a value instead of constraining
/// it as a public input left it unconstrained calldata that a caller could pick freely.
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
    nullifier: pub Field,
) {
    // For M1, this circuit encodes the intended shape.
    // The actual hash primitive (keccak vs Poseidon) is resolved per open
    // question 8.1. The Solidity-side commitment functions in
    // CapabilityCommitment.sol MUST match whatever hash is chosen here.

    assert(nullifier == hash::nullifier(salt));
    assert(
        capability_commitment
            == hash::capability_commitment(
                salt, agent_id, home_chain_id, home_domain_id, capability_index, action_commitment,
                executor, expiry,
            ),
    );
}
