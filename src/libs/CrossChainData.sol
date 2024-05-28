// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


import {OptionsBuilder} from "@lz-oapp-v2/libs/OptionsBuilder.sol";
import "../Structs.sol";

library CrossChainData {
    using OptionsBuilder for bytes;

    // assuming 18 decimals... TODO: Do with other decimals
    function calculateAmountOutMin(uint256 quantity, uint256 units) public pure returns (uint256) {
        uint256 result = (units * quantity) / 1 ether;
        return result;
    }

    function createLzSendOpts(uint128 _gas, uint128 _value) public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }
}
