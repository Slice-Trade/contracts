// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct Chain {
    uint256 chainId;
    bytes32 axelarChain;
    uint16 stargateChainId;
}

struct Position {
    uint256 chainId; // The chain ID where the token is deployed
    address token; // The address of the token in the Position
    uint256 units; // The amount of the given token in the Slice token (i.e. 0.5 wETH)
}