// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {ISliceToken} from "../interfaces/ISliceToken.sol";
import "./ISliceTokenMigrator.sol";
import "./MigratorStructs.sol";

contract SliceTokenMigrator is ISliceTokenMigrator {
    using SafeERC20 for ISliceToken;

    ISliceCore immutable SLICE_CORE;

    mapping(bytes32 migrationId => MigrationInfo) public migrationInfo;

    /**
     * @dev Nonce for each user to guranatee unique hashes for IDs
     */
    mapping(address => uint256) public nonces;

    constructor(ISliceCore sliceCore) {
        SLICE_CORE = sliceCore;
    }

    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount, uint128[] calldata fees)
        external
        payable
    {
        if (!isRegisteredSliceToken(srcAsset) || !isRegisteredSliceToken(dstAsset)) {
            revert UnregisteredSliceToken();
        }

        ISliceToken(srcAsset).safeTransferFrom(msg.sender, address(this), fromAmount);
        bytes32 redeemId = ISliceToken(srcAsset).redeem{value: msg.value}(fromAmount, fees);

        uint256 nonce = nonces[msg.sender]++;

        bytes32 migrationId = keccak256(
            abi.encodePacked(
                this.migrateStep1.selector, block.chainid, msg.sender, srcAsset, dstAsset, fromAmount, nonce
            )
        );

        migrationInfo[migrationId] = MigrationInfo({
            id: migrationId,
            redeemId: redeemId,
            mintId: bytes32(0),
            srcAsset: srcAsset,
            dstAsset: dstAsset,
            fromAmount: fromAmount
        });

        emit MigrateStep1(migrationId);
    }

    function migrateStep2(bytes32 migrationId, uint128[] calldata fees) external payable {}

    function withdraw(bytes32 migrationId) external {}

    function isRegisteredSliceToken(address token) internal view returns (bool) {
        return SLICE_CORE.isSliceTokenRegistered(token);
    }

    receive() external payable {}
}
