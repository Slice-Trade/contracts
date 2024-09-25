// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name,_symbol) {
        _mint(msg.sender, 1000000000000000000000000000);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}

/* [[84532,0xA318b438026f4c243f43f181436980c054950c08,18,1000000000000000000],[11155420,0xB8a2Db09D9DF5180e60bea651964987FcD49213a,18,1000000000000000000]] */