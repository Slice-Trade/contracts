// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenMock is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 24;
    }

}