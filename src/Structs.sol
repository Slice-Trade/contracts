// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The state of a SliceTransactionInfo
enum TransactionState {
    UNREGISTERED,
    OPEN,
    FULFILLED,
    FAILED,
    REFUNDING,
    REFUNDED
}

/// @notice The various cross chain signals the SliceCore can handle
enum CrossChainSignalType {
    MINT,
    MINT_COMPLETE,
    REDEEM,
    REDEEM_COMPLETE,
    REFUND,
    REFUND_COMPLETE
}

/**
 * @notice Info about a specific blockchain
 *
 * @param chainId The actual chain ID
 * @param lzEndpointId Layer Zero chain endpoint ID
 */
struct Chain {
    uint256 chainId;
    uint32 lzEndpointId;
}

/**
 * @notice The Position structs hold information about an underlying asset in a Slice token.
 *
 * @param chainId The chain ID where the token is deployed
 * @param token The address of the token in the Position
 * @param decimals The decimals used in the ERC20 token
 * @param units amount of the given token in the Slice token (i.e. 0.5 wETH)
 */
struct Position {
    uint256 chainId;
    address token;
    uint8 decimals;
    uint256 units;
}

/**
 * @notice Used for passing info to the Slice Core contract in mint,redeem,refund calls.
 *
 * @param id The mint/rebalance/redeem ID created by the token contract
 * @param quantity The quantity of slice tokens being minted/redeemed (not used for rebalance)
 * @param user Address of the user who initiated the transaction
 * @param state the current state of the slice transaction
 */
struct SliceTransactionInfo {
    bytes32 id;
    uint256 quantity;
    address user;
    TransactionState state;
}

/**
 * @notice Used for recording info about complete signals received for a pending transaction
 *
 * @param token The slice token on which the transaction is happening
 * @param signalsOk The number of success complete signals received
 * @param signalsFailed The number of failed complete signals received
 * @param sliceTokenQuantity The quantity of slice tokens in the transaction
 * @param user The user who initiated the transaction
 * @param positionsOkIdxs The indexes of the positions in the Slice token's positions() array that have been successfully transferred
 */
struct TransactionCompleteSignals {
    address token;
    uint256 signalsOk;
    uint256 signalsFailed;
    uint256 sliceTokenQuantity;
    address user;
    uint256[] positionsOkIdxs;
}

/**
 * @notice Used for sending information about a transaction cross-chain
 *
 * @param id The ID of the transaction
 * @param srcChainId Chain ID of the chain that is sending the signal
 * @param ccsType CrossChainSignal type
 * @param success If the operation that resulted in this signal was successful or not
 * @param user The user who initiated the transaction (only used for redeemUnderlying/ manual mint)
 * @param underlying The underlying token the user is redeeming/manual minting (only used for redeemUnderlying/manual mint)
 * @param units The units of the underlying token being redeemed/manual minted (only used for redeemUnderlying/manual mint)
 */
struct CrossChainSignal {
    bytes32 id;
    uint32 srcChainId;
    CrossChainSignalType ccsType;
    bool success;
    address user;
    address underlying;
    uint256 units;
    uint256 value;
}

/**
 * @notice Used to store the amount of gas the core contract sends cross-chain.
 *
 * @param gasForAdapter Gas used in the adapter data field (will be used by Stargate/Axelar adapter)
 * @param gasForPayload Gas used in the payload data field (will be used by the slice core contract on the destination chain)
 */
struct CrossChainGas {
    uint256 gasForAdapter;
    uint256 gasForPayload;
}

struct LzMsgGroupInfo {
    uint256 currentCount;
    uint256 currentChainId;
    uint8 totalMsgCount;
    uint256 positionsLength;
}
