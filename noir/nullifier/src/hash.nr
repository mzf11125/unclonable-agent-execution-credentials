// SPDX-License-Identifier: CC0-1.0

/// @notice Hash helpers for ERC-XXXX Noir circuit.
/// @dev The actual primitive depends on the open question resolution.
///      For M1, keccak256 in-circuit is recommended.
pub fn nullifier(salt: Field) -> Field {
    salt
}

pub fn capability_commitment(
    salt: Field,
    agent_id: Field,
    home_chain_id: Field,
    home_domain_id: Field,
    capability_index: Field,
    action_commitment: Field,
) -> Field {
    salt
}
