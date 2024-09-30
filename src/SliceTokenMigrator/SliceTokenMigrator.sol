// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {MessagingParams, MessagingReceipt} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {ISliceToken} from "../interfaces/ISliceToken.sol";
import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {IChainInfo} from "../interfaces/IChainInfo.sol";

import {
    SliceTransactionInfo, TransactionState, TransactionCompleteSignals, LzMsgGroupInfo, Chain
} from "../Structs.sol";

import {ISliceTokenMigrator} from "./ISliceTokenMigrator.sol";
import {TokenAmountUtils} from "../libs/TokenAmountUtils.sol";
import {LayerZeroUtils} from "../libs/LayerZeroUtils.sol";

import "./MigratorStructs.sol";
import "./MigratorUtils.sol";
import "forge-std/src/console.sol";

contract SliceTokenMigrator is ISliceTokenMigrator, Ownable2Step, ReentrancyGuard, OApp {
    using SafeERC20 for ISliceToken;
    using SafeERC20 for IERC20;

    ISliceCore immutable SLICE_CORE;
    IChainInfo immutable CHAIN_INFO;

    /**
     * @dev Stores info about each migration
     */
    mapping(bytes32 migrationId => MigrationInfo) public migrationInfos;

    /**
     * @dev Keeps track of what actions have been executed already for a migration
     */
    mapping(bytes32 migrationId => MigrationActions) public migrationActions;
    
    /**
     * @dev Nonce for each user to guranatee unique hashes for IDs
     */
    mapping(address => uint256) public nonces;

    /**
     * @dev Stores cross chain gas information for layer zero messages
     */
    mapping(MigratorCrossChainSignalType ccsType => uint128 gas) public lzGasLookup;

    constructor(ISliceCore sliceCore, IChainInfo chainInfo, address _lzEndpoint, address _owner)
        Ownable(_owner)
        OApp(_lzEndpoint, _owner)
    {
        SLICE_CORE = sliceCore;
        CHAIN_INFO = chainInfo;

        // TODO: Gas estimations
        lzGasLookup[MigratorCrossChainSignalType.APPROVE_TRANSFER] = 150_000;
        lzGasLookup[MigratorCrossChainSignalType.WITHDRAW] = 250_000;
    }

    /* =========================================================== */
    /*    ===================    EXTERNAL   ====================   */
    /* =========================================================== */
    /**
     * @dev See ISliceTokenMigrator - migrateStep1
     */
    function migrateStep1(address srcAsset, address dstAsset, uint256 fromAmount, uint128[] calldata fees)
        external
        payable
        nonReentrant
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

        uint256 mintAmount = calculateMintAmount(srcAsset, dstAsset, fromAmount);

        migrationInfos[migrationId] = MigrationInfo({
            id: migrationId,
            redeemId: redeemId,
            mintId: bytes32(0),
            creator: msg.sender,
            srcAsset: srcAsset,
            dstAsset: dstAsset,
            fromAmount: fromAmount,
            mintAmount: mintAmount
        });

        handleMintApprovals(dstAsset, mintAmount);

        emit MigrateStep1(migrationId);
    }

    /**
     * @dev See ISliceTokenMigrator - migrateStep2
     */
    function migrateStep2(bytes32 migrationId, uint128[] calldata fees) external payable nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.srcAsset).getRedeem(migrationInfo.redeemId).state != TransactionState.FULFILLED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].step2Executed) {
            revert ActionAlreadyExecuted("migrateStep2");
        }

        migrationActions[migrationId].step2Executed = true;

        bytes32 mintId = ISliceToken(migrationInfo.dstAsset).mint{value: msg.value}(migrationInfo.mintAmount, fees);
        migrationInfos[migrationId].mintId = mintId;

        emit MigrateStep2(migrationId);
    }

    /**
     * @dev See ISliceTokenMigrator - withdrawMintedSlice
     */
    function withdrawMintedSlice(bytes32 migrationId) external nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.dstAsset).getMint(migrationInfo.mintId).state != TransactionState.FULFILLED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].mintedSliceWithdrawn) {
            revert ActionAlreadyExecuted("withdrawMintedSlice");
        }

        migrationActions[migrationId].mintedSliceWithdrawn = true;

        ISliceToken(migrationInfo.dstAsset).safeTransfer(migrationInfo.creator, migrationInfo.mintAmount);

        emit Withdraw(migrationId);
    }

    /**
     * @dev See ISliceTokenMigrator - withdrawLeftoverAssets
     */
    function withdrawLeftoverAssets(bytes32 migrationId) external payable nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.dstAsset).getMint(migrationInfo.mintId).state != TransactionState.FULFILLED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].leftoversWithdrawn) {
            revert ActionAlreadyExecuted("withdrawLeftoverAssets");
        }

        migrationActions[migrationId].leftoversWithdrawn = true;

        MigratePosition[] memory common = MigratorUtils.getCommonAssets(
            ISliceToken(migrationInfo.srcAsset).getPositions(), ISliceToken(migrationInfo.dstAsset).getPositions()
        );

        uint256 commonLength = common.length;
        MigratorCrossChainSignal[] memory ccMsgs = new MigratorCrossChainSignal[](commonLength);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, commonLength, msg.value);

        for (uint256 i = 0; i < commonLength; i++) {
            uint256 amountRedeemed =
                TokenAmountUtils.calculateAmountOutMin(migrationInfo.fromAmount, common[i].unitsA, common[i].decimals);

            uint256 amountUsedForMint =
                TokenAmountUtils.calculateAmountOutMin(migrationInfo.mintAmount, common[i].unitsB, common[i].decimals);

            uint256 transferAmount;
            if (amountRedeemed <= amountUsedForMint) {
                continue;
            }
            // we need to transfer the difference
            transferAmount = amountRedeemed - amountUsedForMint;
            if (isPositionLocal(common[i].chainId)) {
                IERC20(common[i].token).safeTransfer(migrationInfo.creator, transferAmount);
            } else {
                MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
                    ccsType: MigratorCrossChainSignalType.WITHDRAW,
                    underlying: common[i].token,
                    user: migrationInfo.creator,
                    amount: transferAmount
                });
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, common[i].chainId, lzMsgInfo);
            }
        }
        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, migrationInfo.creator);
        }
    }

    /**
     * @dev See ISliceTokenMigrator - withdrawRedeemedAssets
     */
    function withdrawRedeemedAssets(bytes32 migrationId) external payable nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.dstAsset).getMint(migrationInfo.mintId).state != TransactionState.FULFILLED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].redeemedWithdrawn) {
            revert ActionAlreadyExecuted("withdrawRedeemedAssets");
        }
        migrationActions[migrationId].redeemedWithdrawn = true;

        Position[] memory redeemed = MigratorUtils.getSliceAOnlyAssets(
            ISliceToken(migrationInfo.srcAsset).getPositions(), ISliceToken(migrationInfo.dstAsset).getPositions()
        );

        uint256 redeemedLength = redeemed.length;
        MigratorCrossChainSignal[] memory ccMsgs = new MigratorCrossChainSignal[](redeemedLength);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, redeemedLength, msg.value);

        for (uint256 i = 0; i < redeemedLength; i++) {
            uint256 amountRedeemed = TokenAmountUtils.calculateAmountOutMin(
                migrationInfo.fromAmount, redeemed[i].units, redeemed[i].decimals
            );

            if (isPositionLocal(redeemed[i].chainId)) {
                IERC20(redeemed[i].token).safeTransfer(migrationInfo.creator, amountRedeemed);
            } else {
                MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
                    ccsType: MigratorCrossChainSignalType.WITHDRAW,
                    underlying: redeemed[i].token,
                    user: migrationInfo.creator,
                    amount: amountRedeemed
                });
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, redeemed[i].chainId, lzMsgInfo);
            }
        }

        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, migrationInfo.creator);
        }
    }

    /**
     * @dev See ISliceTokenMigrator - refund
     */
    function refund(bytes32 migrationId, uint128[] calldata fees) external payable nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.dstAsset).getMint(migrationInfo.mintId).state != TransactionState.FAILED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].failedMintRefunded) {
            revert ActionAlreadyExecuted("refund");
        }

        migrationActions[migrationId].failedMintRefunded = true;

        ISliceToken(migrationInfo.dstAsset).refund{value: msg.value}(migrationInfo.mintId, fees);
    }

    /**
     * @dev See ISliceTokenMigrator - withdrawRefund
     */
    function withdrawRefund(bytes32 migrationId) external payable nonReentrant {
        MigrationInfo memory migrationInfo = migrationInfos[migrationId];
        if (migrationInfo.creator != msg.sender) {
            revert Unauthorized();
        }

        if (ISliceToken(migrationInfo.dstAsset).getMint(migrationInfo.mintId).state != TransactionState.REFUNDED) {
            revert InvalidTransactionState();
        }

        if (migrationActions[migrationId].refundWithdrawn) {
            revert ActionAlreadyExecuted("withdrawRefund");
        }

        migrationActions[migrationId].refundWithdrawn = true;

        TransactionCompleteSignals memory _txCompleteSignal =
            SLICE_CORE.getTransactionCompleteSignal(migrationInfo.mintId);

        Position[] memory dstPositions = ISliceToken(migrationInfo.dstAsset).getPositions();

        MigratorCrossChainSignal[] memory ccMsgs =
            new MigratorCrossChainSignal[](_txCompleteSignal.positionsOkIdxs.length);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, _txCompleteSignal.positionsOkIdxs.length, msg.value);

        for (uint256 i = 0; i < _txCompleteSignal.positionsOkIdxs.length; i++) {
            uint256 _posIdx = _txCompleteSignal.positionsOkIdxs[i];
            uint256 _amountOut = TokenAmountUtils.calculateAmountOutMin(
                migrationInfo.mintAmount, dstPositions[_posIdx].units, dstPositions[_posIdx].decimals
            );

            if (isPositionLocal(dstPositions[_posIdx].chainId)) {
                IERC20(dstPositions[_posIdx].token).safeTransfer(migrationInfo.creator, _amountOut);
            } else {
                MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
                    ccsType: MigratorCrossChainSignalType.WITHDRAW,
                    underlying: dstPositions[_posIdx].token,
                    user: migrationInfo.creator,
                    amount: _amountOut
                });
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, dstPositions[_posIdx].chainId, lzMsgInfo);
            }
        }

        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, migrationInfo.creator);
        }
    }

    function withdrawDust(address to) external nonReentrant onlyOwner {
        (bool success,) = to.call{value: address(this).balance}("");
        if (!success) {
            revert WithdrawFailed();
        }
    }

    /* =========================================================== */
    /*    ===================    INTERNAL   ====================   */
    /* =========================================================== */
    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32, /* _guid */ // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address, /* _executor */ // the Executor address.
        bytes calldata /* _extraData */ // arbitrary data appended by the Executor
    ) internal override {
        if (address(uint160(uint256(_origin.sender))) != address(this)) {
            revert OriginNotVault();
        }

        MigratorCrossChainSignal[] memory ccs = abi.decode(payload, (MigratorCrossChainSignal[]));

        MigratorCrossChainSignalType ccsType = ccs[0].ccsType;

        if (ccsType == MigratorCrossChainSignalType.APPROVE_TRANSFER) {
            handleApproveSignal(ccs);
        } else if (ccsType == MigratorCrossChainSignalType.WITHDRAW) {
            handleWithdrawSignal(ccs);
        }
    }

    function handleApproveSignal(MigratorCrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            IERC20(ccs[i].underlying).approve(ccs[i].user, ccs[i].amount);
        }
    }

    function handleWithdrawSignal(MigratorCrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            IERC20(ccs[i].underlying).safeTransfer(ccs[i].user, ccs[i].amount);
        }
    }

    function isRegisteredSliceToken(address token) internal view returns (bool) {
        return SLICE_CORE.isSliceTokenRegistered(token);
    }

    function groupAndSendLzMsg(
        MigratorCrossChainSignal[] memory ccMsgs,
        MigratorCrossChainSignal memory ccs,
        uint256 positionChainId,
        LzMsgGroupInfo memory lzMsgInfo
    ) internal returns (MigratorCrossChainSignal[] memory, LzMsgGroupInfo memory) {
        if (lzMsgInfo.currentChainId == positionChainId) {
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            ++lzMsgInfo.currentCount;
        } else {
            if (lzMsgInfo.currentChainId != 0) {
                (ccMsgs, lzMsgInfo) = _sendGroupedLzMsg(ccMsgs, ccs, lzMsgInfo, address(this));

                lzMsgInfo.currentCount = 0;
                lzMsgInfo.currentChainId = positionChainId;
                ccMsgs = new MigratorCrossChainSignal[](lzMsgInfo.positionsLength);
            }
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            lzMsgInfo.currentChainId = positionChainId;
            ++lzMsgInfo.currentCount;
        }
        return (ccMsgs, lzMsgInfo);
    }

    function _sendGroupedLzMsg(
        MigratorCrossChainSignal[] memory ccMsgs,
        MigratorCrossChainSignal memory ccs,
        LzMsgGroupInfo memory lzMsgInfo,
        address refundAddress
    ) private returns (MigratorCrossChainSignal[] memory, LzMsgGroupInfo memory) {
        {
            uint256 currentCount = lzMsgInfo.currentCount;
            assembly {
                mstore(ccMsgs, currentCount)
            }
        }
        bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
        Chain memory dstChain = CHAIN_INFO.getChainInfo(lzMsgInfo.currentChainId);

        bytes memory _lzSendOpts = LayerZeroUtils.createLzSendOpts({
            _gas: requiredGas(ccs.ccsType, uint128(lzMsgInfo.currentCount)),
            _value: 0
        });

        MessagingReceipt memory receipt = _lzSend(
            dstChain.lzEndpointId, ccsMsgsEncoded, _lzSendOpts, MessagingFee(lzMsgInfo.providedFee, 0), refundAddress
        );
        ++lzMsgInfo.totalMsgCount;
        lzMsgInfo.providedFee -= receipt.fee.nativeFee;

        return (ccMsgs, lzMsgInfo);
    }

    function calculateMintAmount(address srcAsset, address dstAsset, uint256 fromAmount)
        internal
        view
        returns (uint256 mintAmount)
    {
        Position[] memory dstAssetPositions = ISliceToken(dstAsset).getPositions();
        MigratePosition[] memory common =
            MigratorUtils.getCommonAssets(ISliceToken(srcAsset).getPositions(), dstAssetPositions);

        if (common.length == 0) {
            revert NoAssetsInCommon();
        }
        
        mintAmount = type(uint256).max;
        // calculate how much we can mint from SliceB
        for (uint256 i = 0; i < common.length; i++) {
            // this is the amount that was received during the redeem
            uint256 assetIn = TokenAmountUtils.calculateAmountOutMin(fromAmount, common[i].unitsA, common[i].decimals);
            // this is the slice token amount we can get for this amount of assetIn
            uint256 minMintable = TokenAmountUtils.calculateAmountInMin(assetIn, common[i].unitsB, common[i].decimals);
            // we get the smallest one
            if (minMintable < mintAmount) {
                mintAmount = minMintable;
            }
        }

        if (mintAmount == type(uint256).max) {
            revert InvalidMintAmount();
        }
    }

    function handleMintApprovals(address dstAsset, uint256 mintAmount) internal {
        Position[] memory dstAssetPositions = ISliceToken(dstAsset).getPositions();

        uint256 dstAssetPositionsLength = dstAssetPositions.length;
        MigratorCrossChainSignal[] memory ccMsgs = new MigratorCrossChainSignal[](dstAssetPositionsLength);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, dstAssetPositionsLength, msg.value);

        for (uint256 i = 0; i < dstAssetPositionsLength; i++) {
            uint256 approveAmount = TokenAmountUtils.calculateAmountOutMin(
                mintAmount, dstAssetPositions[i].units, dstAssetPositions[i].decimals
            );
            if (isPositionLocal(dstAssetPositions[i].chainId)) {
                IERC20(dstAssetPositions[i].token).approve(address(SLICE_CORE), approveAmount);
            } else {
                MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
                    ccsType: MigratorCrossChainSignalType.APPROVE_TRANSFER,
                    underlying: dstAssetPositions[i].token,
                    user: address(SLICE_CORE),
                    amount: approveAmount
                });

                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, dstAssetPositions[i].chainId, lzMsgInfo);
            }
        }

        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, msg.sender);
        }
    }

    function requiredGas(MigratorCrossChainSignalType ccsType, uint128 msgsLength) internal view returns (uint128) {
        uint128 _baseGas = lzGasLookup[ccsType];
        uint128 _gasStep = gasStep(ccsType);

        uint128 gasRequired = _baseGas + (_gasStep * msgsLength);

        return gasRequired;
    }

    // TODO: Gas estimations
    function gasStep(MigratorCrossChainSignalType ccsType) internal pure returns (uint128) {
        if (ccsType == MigratorCrossChainSignalType.APPROVE_TRANSFER) {
            return 10_000;
        }
        return 25_000;
    }

    function isPositionLocal(uint256 positionChainId) internal view returns (bool) {
        return positionChainId == block.chainid;
    }

    /* =========================================================== */
    /*    ================    OWNABLE2STEP    ==================   */
    /* =========================================================== */
    /**
     * @dev This must be overriden because OApp uses Ownable without 2 step. SliceCore uses Ownable2Step everywhere.
     */
    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    /**
     * @dev This must be overriden because OApp uses Ownable without 2 step. SliceCore uses Ownable2Step everywhere.
     */
    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }

    /* =========================================================== */
    /*    =================    OAPP LZSEND    ==================   */
    /* =========================================================== */
    /// @dev Batch send requires overriding this function from OAppSender because the msg.value contains multiple fees
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    receive() external payable {}
}
