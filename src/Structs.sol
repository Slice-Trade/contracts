// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

enum TransactionState {
    UNREGISTERED,
    OPEN,
    FULFILLED
}

/**
 * @dev Axelar and Stargate have different internal nomenclature for the blockchain chain IDs.
 *      We store these and use the real chain ID for internal recording.
 *
 * @param chainId The actual chain ID
 * @param axelarChainId Chain ID as represented within Axelar
 * @param stargateChainId Chain ID as represented within Stargate 
 * @param lzEndpointId Layer Zero chain endpoint ID
 * @param stargateAdapter The address of stargate adapter on the chain 
 * @param paymentToken Payment token on the dst chain
 */
struct Chain {
    uint256 chainId;
    bytes32 axelarChainId;
    uint16 stargateChainId;
    uint32 lzEndpointId;
    address stargateAdapter;
    address paymentToken;
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
 * @dev Used for passing info to the Slice Core contract in mint,redeem,balance calls.
 * @param id The mint/rebalance/redeem ID created by the token contract
 * @param quantity The quantity of slice tokens being minted/redeemed (not used for rebalance)
 * @param user Address of the user who initiated the transaction
 * @param data Arbitrary data. Initially empty, later can be used to pass in non-EVM user addresses.
 */
struct SliceTransactionInfo {
    bytes32 id;
    uint256 quantity;
    address user;
    TransactionState state;
    bytes data;
}

struct TransactionCompleteSignals {
    address token;
    uint256 signals;
    uint256 sliceTokenQuantity;
    address user;
}

enum TransactionType {
    MINT,
    REDEEM
}

struct CrossChainSignal {
    bytes32 id;
    TransactionType txType;
    bool success;
    address underlying;
    uint256 units;
}

struct SlicePayloadData {
    uint256 srcChainId;
    bytes32 mintID;
    address tokenOut;
    uint256 amountOutMin;
    bytes data;
}