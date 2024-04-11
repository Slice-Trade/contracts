// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../Structs.sol";

interface ISliceTokenDeployer {
    function deploySliceToken(
        string calldata _name,
        string calldata _symbol,
        Position[] calldata _positions,
        address _paymentToken,
        address _core
    ) external returns (address);
}