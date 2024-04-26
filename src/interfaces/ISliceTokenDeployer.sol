// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../Structs.sol";

interface ISliceTokenDeployer {
    /**
     * @dev Deploys a new slice token
     *
     * @param name The name of the slice token
     * @param symbol The slice token's symbol
     * @param positions The underlying positions in the slice
     * @param paymentToken Token used for paying for the slice
     * @param core The SliceCore.sol contract address
     *
     * @return address The address of the new slice token
     */
    function deploySliceToken(
        string calldata name,
        string calldata symbol,
        Position[] calldata positions,
        address paymentToken,
        address core
    ) external returns (address);
}