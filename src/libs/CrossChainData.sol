// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OptionsBuilder} from "@lz-oapp-v2/libs/OptionsBuilder.sol";
import "../Structs.sol";

library CrossChainData {
    using OptionsBuilder for bytes;

    function calculateAmountOutMin(uint256 quantity, uint256 units, uint8 decimals) public pure returns (uint256) {
        quantity = convertDecimals(quantity, decimals);

        uint256 result = (units * quantity) / 10**decimals;
        
        return result;
    }

    function getMinimumAmountInSliceToken(uint8 tokenBDecimals) public pure returns (uint256) {
        uint8 tokenADecimals = 18;
        if (tokenADecimals <= tokenBDecimals) {
            return 1;
        }

        uint8 difference = tokenADecimals - tokenBDecimals;
        return 10 ** difference;
    }

    function convertDecimals(uint256 amount, uint8 toDecimals) public pure returns (uint256) {
        uint8 fromDecimals = 18;
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            uint8 difference = fromDecimals - toDecimals;
            return amount / (10 ** difference);
        } else {
            uint8 difference = toDecimals - fromDecimals;
            return amount * (10 ** difference);
        }
    }

    function createLzSendOpts(uint128 _gas, uint128 _value) public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }
}
