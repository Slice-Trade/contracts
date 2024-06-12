// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../SliceToken.sol";
import "../interfaces/ISliceTokenDeployer.sol";

contract SliceTokenDeployer is ISliceTokenDeployer {
    function deploySliceToken(
        string calldata name,
        string calldata symbol,
        Position[] calldata positions,
        address core
    ) external returns (address) {
        SliceToken token = new SliceToken(name, symbol, positions, core);
        return address(token);
    }
}
