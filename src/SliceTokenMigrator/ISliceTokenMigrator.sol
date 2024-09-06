// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {TransactionCompleteSignals} from "../Structs.sol";

interface ISliceTokenMigrator {
    event MigrateStep1(bytes32 indexed migrationId);
    event MigrateStep2(bytes32 indexed migrationId);
    event Withdraw(bytes32 indexed migrationId);

    error UnregisteredSliceToken();

    error Unauthorized();

    error InvalidTransactionState();

    error WithdrawFailed();

    error ActionAlreadyExecuted(string action);

    error OriginNotVault();

    error InvalidMintAmount();

    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount, uint128[] calldata fees)
        external
        payable;

    function migrateStep2(bytes32 migrationId, uint128[] calldata fees) external payable;

    function withdrawMintedSlice(bytes32 migrationId) external;
}

/// @dev ISliceCore interface, but with an extra function to get the value from the public mapping transactionCompleteSignals
interface ISliceCore2 is ISliceCore {
    function transactionCompleteSignals(bytes32 id) external view returns (TransactionCompleteSignals memory);
}
