// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../SliceToken.sol";
import "../interfaces/ISliceTokenDeployer.sol";

contract SliceTokenDeployer is ISliceTokenDeployer {
    function deploySliceToken(
        string calldata name,
        string calldata symbol,
        Position[] calldata positions,
        address paymentToken,
        address core
    ) external returns (address) {
        SliceToken token = new SliceToken(name, symbol, positions, paymentToken, core);
        return address(token);
    }
}
