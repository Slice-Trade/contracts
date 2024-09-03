// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The cross-chain signals the CrossChainVault can handle
enum CrossChainVaultSignalType {
    COMMIT,
    COMMIT_COMPLETE,
    REMOVE,
    REMOVE_COMPLETE
}

/// @notice Commitment is committed when user provided assets, pulled when he already pulled the minted slice tokens
enum CommitmentState {
    COMMITTED,
    PULLED
}

/**
 * @notice Holds info about created commitemnt strategies
 *
 * @param id The ID of the strategy
 * @param creator The address that created this strategy
 * @param token The Slice Token this strategy mints
 * @param target The amount of Slice token this strategy will mint
 * @param isPrivate Whether this strategy is private or public
 * @param nonce Nonce increases every time startegy is executed
 */
struct CommitmentStrategy {
    bytes32 id;
    address creator;
    address token;
    uint256 target;
    bool isPrivate;
    uint256 nonce;
}

/**
 * @notice Holds info about a user's commitment to a strategy
 *
 * @param id The ID of the commitment
 * @param strategyId The strategy ID to which the user committed
 * @param commitmentState State of the commitment
 * @param creator The user who commits to the strategy
 * @param chainId The chain ID where the underlying asset committed lives
 * @param asset The address of the underlying asset
 * @param decimals The decimals of the underlying asset
 * @param committed Amount committed of the underlying asset
 * @param strategyNonce The nonce at which the user committed to the startegy
 */
struct Commitment {
    bytes32 id;
    bytes32 strategyId;
    CommitmentState commitmentState;
    address creator;
    uint256 chainId;
    address asset;
    uint8 decimals;
    uint256 committed;
    uint256 strategyNonce;
}

/**
 * @notice Stores the Chainlink price feed update for the given underlying asset
 *
 * @param id Unique ID identifying this price update
 * @param token The address of the underlying asset
 * @param decimals The decimals of the underlying asset
 * @param price The USD price of the underlying asset
 * @param updateTimestamp The timestamp when the price was updated
 */
struct OraclePriceUpdate {
    bytes32 id;
    address token;
    uint8 decimals;
    uint256 price;
    uint256 updateTimestamp;
}

/**
 * @notice Used for sending information about a transaction cross-chain
 *
 * @param id Either the strategy or commitment ID, depending on the type of signal
 * @param srcChainId The chain ID where the message is coming from
 * @param ccvsType The type of the signal
 * @param user The user who initiated the transaction
 * @param underlying The underlying asset
 * @param decimals The decimals of the underlying asset
 * @param amount The amount of the underlying asset
 * @param value The msg.value for the cross-chain message
 */
struct CrossChainVaultSignal {
    bytes32 id;
    uint32 srcChainId;
    CrossChainVaultSignalType ccvsType;
    address user;
    address underlying;
    uint8 decimals;
    uint256 amount;
    uint256 value;
}
