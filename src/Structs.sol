// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @notice The state of a SliceTransactionInfo
enum TransactionState {
    UNREGISTERED,
    OPEN,
    FULFILLED,
    FAILED,
    REFUNDING,
    REFUNDED
}

/// @notice 
enum CrossChainSignalType {
    MANUAL_MINT,
    MINT_COMPLETE,
    REDEEM,
    REDEEM_COMPLETE,
    REFUND,
    REFUND_COMPLETE
}

/**
 * @notice Axelar and Stargate have different internal nomenclature for the blockchain chain IDs.
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
 * @notice The Position structs hold information about an underlying asset in a Slice token.
 *
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
 * @notice Used for passing info to the Slice Core contract in mint,redeem,balance calls.
 *
 * @param id The mint/rebalance/redeem ID created by the token contract
 * @param quantity The quantity of slice tokens being minted/redeemed (not used for rebalance)
 * @param user Address of the user who initiated the transaction
 * @param state the current state of the slice transaction
 * @param data Arbitrary data. Initially empty, later can be used to pass in non-EVM user addresses.
 */
struct SliceTransactionInfo {
    bytes32 id;
    uint256 quantity;
    address user;
    TransactionState state;
    bytes data;
}

 /** 
  * @notice Used for recording info about complete signals received for a pending transaction
  *
  * @param token The slice token on which the transaction is happening
  * @param signalsOk The number of success complete signals received
  * @param signalsFailed The number of failed complete signals received
  * @param sliceTokenQuantity The quantity of slice tokens in the transaction
  * @param user The user who initiated the transaction
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
}

/**
 * @notice The payload we are sending cross-chain to the SliceCore contract
 *
 * @param srcChainId The chain id of the chain that is sending this payload
 * @param mintID The mint ID of the transaction
 * @param tokenOut The token the SliceCore should have received
 * @param The amount of token the SliceCore should have received
 * @param data Additional data field, not used. Can be used later to encode solana address.
 */
struct SlicePayloadData {
    uint256 srcChainId;
    bytes32 mintID;
    address tokenOut;
    uint256 amountOutMin;
    bytes data;
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