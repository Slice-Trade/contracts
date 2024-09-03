// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISliceCore} from "../interfaces/ISliceCore.sol";
import "./ISliceTokenMigrator.sol";
import "./MigratorStructs.sol";

contract SliceTokenMigrator is ISliceTokenMigrator {
    ISliceCore immutable SLICE_CORE;

    mapping(bytes32 migrationId => MigrationInfo) public migrationInfo;

    constructor(ISliceCore sliceCore) {
        SLICE_CORE = sliceCore;
    }

    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount) external {}

    function migrateStep2(bytes32 migrationId) external {}

    function withdraw(bytes32 migrationId) external {}

    function isRegisteredSliceToken(address token) internal view returns (bool) {
        return SLICE_CORE.isSliceTokenRegistered(token);
    }
}
