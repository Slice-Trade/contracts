// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../SliceToken.sol";
import "../interfaces/ISliceTokenDeployer.sol";

contract SliceTokenDeployer is ISliceTokenDeployer {
    function deploySliceToken(
        string calldata _name,
        string calldata _symbol,
        Position[] calldata _positions,
        address _paymentToken,
        address _core
    ) external returns (address) {
        SliceToken token = new SliceToken(_name, _symbol, _positions, _paymentToken, _core);
        return address(token);
    }
}
