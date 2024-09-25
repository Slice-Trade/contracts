// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OptionsBuilder} from "@lz-oapp-v2/libs/OptionsBuilder.sol";

library LayerZeroUtils {
    using OptionsBuilder for bytes;

    function createLzSendOpts(uint128 _gas, uint128 _value) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }
}
