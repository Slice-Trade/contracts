// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum CrossChainVaultSignalType {
    COMMIT,
    COMMIT_COMPLETE,
    REMOVE,
    REMOVE_COMPLETE
}

enum CommitmentState {
    COMMITTED,
    PULLED
}

struct CommitmentStrategy {
    bytes32 id;
    address creator;
    address token;
    uint256 target;
    bool isPrivate;
    uint256 nonce;
}

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

struct OraclePriceUpdate {
    bytes32 id;
    address token;
    uint8 decimals;
    uint256 price;
    uint256 updateTimestamp;
}

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
