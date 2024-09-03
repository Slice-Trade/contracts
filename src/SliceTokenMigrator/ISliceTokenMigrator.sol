// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISliceTokenMigrator {
    event MigrateStep1(bytes32 indexed migrationId);
    event MigrateStep2(bytes32 indexed migrationId);
    event Withdraw(bytes32 indexed migrationId);

    error UnregisteredSliceToken();

    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount) external;

    function migrateStep2(bytes32 migrationId) external;

    function withdraw(bytes32 migrationId) external;
}
