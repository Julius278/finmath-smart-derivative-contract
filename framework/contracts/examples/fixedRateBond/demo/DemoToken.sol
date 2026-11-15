// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply ERC-20 for local examples; the complete supply exists at deployment.
/// @dev Zero decimals: bond tokens represent denominations; cash uses the bond's integer scale.
contract DemoToken is ERC20 {
    constructor(string memory name_, string memory symbol_, address initialHolder, uint256 initialSupply)
        ERC20(name_, symbol_)
    {
        require(initialHolder != address(0), "holder required");
        _mint(initialHolder, initialSupply);
    }

    function decimals() public pure override returns (uint8) { return 0; }
}
