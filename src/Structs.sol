// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @dev Axelar and Stargate have different internal nomenclature for the blockchain chain IDs.
 *      We store these and use the real chain ID for internal recording.
 *
 * @param chainId The actual chain ID
 * @param axelarChainId Chain ID as represented within Axelar
 * @param stargateChainId Chain ID as represented within Stargate 
 */
struct Chain {
    uint256 chainId;
    bytes32 axelarChainId;
    uint16 stargateChainId;
}

/**
 * @dev The Position structs hold information about an underlying asset in a Slice token.
 * @param chainId The chain ID where the token is deployed
 * @param token The address of the token in the Position
 * @param units amount of the given token in the Slice token (i.e. 0.5 wETH)
 */
struct Position {
    uint256 chainId;
    address token;
    uint256 units;
}

/**
 * RedeemInfo is used by redeemUnderlying in the Slice Core contract.
 * @param sliceToken The slice token whose underlying assets the user is redeeming
 * @param amount The amount of slice tokens the user is redeeming
 * @param user Address of the user doing the redeeming
 * @param data Arbitrary data parameter. Initially empty, later can be used to pass in non-EVM user addresses.
 */
struct RedeemInfo {
    address sliceToken;
    uint256 amount;
    address user;
    bytes data;
}
