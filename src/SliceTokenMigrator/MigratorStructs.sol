// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct MigrationInfo {
    bytes32 id;
    bytes32 redeemId;
    bytes32 mintId;
    address srcAsset;
    address dstAsset;
    uint256 fromAmount;
}