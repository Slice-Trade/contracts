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

    /**
     * @dev Starts the migration procedure from one slice token to another
     *
     * @param srcAsset The Slice token where we are migrating from
     * @param dstAsset The Slice token where we are migrating to
     * @param fromAmount The amount of srcAsset we migrate to dstAsset
     * @param fees Fees paid to the SliceCore.redeem call on LayerZero
     */
    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount, uint128[] calldata fees)
        external
        payable;

    /**
     * @dev Must be called when migrateStep1 is done, so we have the redeemed assets in the migrator contract
     *
     * @param migrationId The ID of the migration from migrateStep1
     * @param fees Fees paid to the SliceCore.redeem call on LayerZero
     */
    function migrateStep2(bytes32 migrationId, uint128[] calldata fees) external payable;

    /**
     * @dev Withdraws the minted dst asset slice tokens after migrateStep2 is successful
     *
     * @param migrationId The ID of the migration
     */
    function withdrawMintedSlice(bytes32 migrationId) external;

    /**
     * @dev Withdraws any leftovers from the common assets that have not been used during the mint
     *
     * @param migrationId The ID of the migration
     */
    function withdrawLeftoverAssets(bytes32 migrationId) external payable;

    /**
     * @dev Withdraws the redeemed assets of the source slice token that are not common with the destination slice token,
     * so they wont be used during the mint
     *
     * @param migrationId The ID of the migration
     */
    function withdrawRedeemedAssets(bytes32 migrationId) external payable;

    /**
     * @dev Mint can still fail if the user does not transfer the necessary assets to the migrator on the dst chain. In this case we must refund
     *
     * @param migrationId The ID of the migration
     */
    function refund(bytes32 migrationId, uint128[] calldata fees) external payable;

    /**
     * @dev Withdraws the refunded assets to the user after a successful refund
     *
     * @param migrationId The ID of the migration
     */
    function withdrawRefund(bytes32 migrationId) external payable;
}

/// @dev ISliceCore interface, but with an extra function to get the value from the public mapping transactionCompleteSignals
interface ISliceCore2 is ISliceCore {
    function transactionCompleteSignals(bytes32 id) external view returns (TransactionCompleteSignals memory);
}
