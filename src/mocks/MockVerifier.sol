// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IVerifier} from "../verifier/IVerifier.sol";

/// @title MockVerifier — Always-True Verifier for Unit Isolation
/// @notice Used only in M0 tests. MUST NOT be used in production.
contract MockVerifier is IVerifier {
    function verify(
        bytes calldata,
        bytes32[] calldata
    ) external pure override returns (bool) {
        return true;
    }
}
