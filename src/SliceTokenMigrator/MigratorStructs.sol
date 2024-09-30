// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct MigrationInfo {
    bytes32 id;
    bytes32 redeemId;
    bytes32 mintId;
    address creator;
    address srcAsset;
    address dstAsset;
    uint256 fromAmount;
    uint256 mintAmount;
}

struct MigrationActions {
    bool step2Executed;
    bool mintedSliceWithdrawn;
    bool leftoversWithdrawn;
    bool redeemedWithdrawn;
    bool failedMintRefunded;
    bool refundWithdrawn;
}

struct MigratePosition {
    uint256 chainId;
    address token;
    uint8 decimals;
    uint256 unitsA;
    uint256 unitsB;
}

enum MigratorCrossChainSignalType {
    APPROVE_TRANSFER,
    WITHDRAW
}

struct MigratorCrossChainSignal {
    MigratorCrossChainSignalType ccsType;
    address underlying;
    address user;
    uint256 amount;
}