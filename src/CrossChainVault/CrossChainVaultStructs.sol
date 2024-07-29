// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum CommitmentStrategyType {
    AMOUNT_TARGET,
    TIMESTAMP_TARGET,
    TIME_INTERVAL_TARGET
}

enum CommitmentStrategyState {
    OPEN,
    EXECUTED
}

enum CrossChainVaultSignalType {
    COMMIT,
    COMMIT_COMPLETE,
    REMOVE,
    REMOVE_COMPLETE
}

struct CommitmentStrategy {
    bytes32 id;
    CommitmentStrategyType strategyType;
    CommitmentStrategyState strategyState;
    address creator;
    address token;
    uint256 target;
    bool isPrivate;
}

struct Commitment {
    bytes32 id;
    bytes32 strategyId;
    uint256 chainId;
    address asset;
    uint256 committed;
    uint256 consumed;
}

struct OraclePriceUpdate {
    bytes32 id;
    address token;
    uint256 price;
    uint256 updateTimestamp;
}

struct SliceTokenShare {
    bytes32 strategyId;
    bytes32 commitmentId;
    bytes32 priceUpdateId;
    address user;
    uint256 sliceTokenShares;
}

struct CrossChainVaultSignal {
    bytes32 strategyId;
    uint32 srcChainId;
    CrossChainVaultSignalType ccvsType;
    address user;
    address underlying;
    uint256 committed;
}