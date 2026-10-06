// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Pegzeus (PEGZEUS)
/// @notice A fixed-supply, fee-free ERC-20 with 18 decimals.
/// @dev The immediate deployer receives all tokens, including when deployed by a factory.
contract Pegzeus is ERC20 {
    /// @notice One billion tokens expressed in the smallest unit (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Pegzeus", "PEGZEUS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
