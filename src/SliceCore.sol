// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessagingParams, MessagingReceipt} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IChainInfo} from "./interfaces/IChainInfo.sol";
import {ISliceCore} from "./interfaces/ISliceCore.sol";
import {ISliceTokenDeployer} from "./interfaces/ISliceTokenDeployer.sol";

import {CrossChainData} from "./libs/CrossChainData.sol";

import {SliceToken, ISliceToken} from "./SliceToken.sol";

import "./Structs.sol";

/**
 * @author Lajos Deme, Blind Labs
 * @notice The core logic contract of the architecture, provides cross-chain underlying asset management
 */
contract SliceCore is ISliceCore, Ownable, OApp, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IChainInfo public immutable chainInfo;

    address public immutable sliceTokenDeployer;

    bool public isTokenCreationEnabled;

    mapping(address creator => bool isApproved) public approvedSliceTokenCreators;

    mapping(address token => bool isRegistered) public registeredSliceTokens;
    address[] public registeredSliceTokensArray;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 id => TransactionCompleteSignals signal) public transactionCompleteSignals;
    mapping(bytes32 id => uint256) refundSignals;

    mapping(CrossChainSignalType ccsType => uint128 gas) public lzGasLookup;

    constructor(address _lzEndpoint, address _chainInfo, address _sliceTokenDeployer, address _owner)
        Ownable(_owner)
        OApp(_lzEndpoint, _owner)
    {
        chainInfo = IChainInfo(_chainInfo);
        sliceTokenDeployer = _sliceTokenDeployer;

        lzGasLookup[CrossChainSignalType.MINT] = 300000;
        lzGasLookup[CrossChainSignalType.MINT_COMPLETE] = 150000;
        lzGasLookup[CrossChainSignalType.REDEEM] = 200000;
        lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE] = 150000;
        lzGasLookup[CrossChainSignalType.REFUND] = 250000;
        lzGasLookup[CrossChainSignalType.REFUND_COMPLETE] = 200000;
    }

    /* =========================================================== */
    /*   ===================    EXTERNAL   ====================    */
    /* =========================================================== */
    /**
     * @dev See ISliceCore - createSlice
     */
    function createSlice(string calldata name, string calldata symbol, Position[] calldata positions)
        external
        nonReentrant
        returns (address)
    {
        if (!canCreateSlice(msg.sender)) {
            revert UnauthorizedCaller();
        }

        if (!isTokenCreationEnabled) {
            revert TokenCreationDisabled();
        }

        address token = ISliceTokenDeployer(sliceTokenDeployer).deploySliceToken({
            name: name,
            symbol: symbol,
            positions: positions,
            core: address(this)
        });

        registeredSliceTokens[token] = true;
        registeredSliceTokensArray.push(token);
        ++registeredSliceTokensCount;

        emit SliceTokenCreated(token);

        return token;
    }

    /**
     * @dev See ISliceCore - collectUnderlying
     */

    function collectUnderlying(bytes32 mintID, uint256[] calldata fees) external payable nonReentrant {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }

        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(mintID);
        if (txInfo.id != mintID || txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        uint256 _sliceTokenQuantity = txInfo.quantity;

        transactionCompleteSignals[mintID].token = msg.sender;
        transactionCompleteSignals[mintID].sliceTokenQuantity = _sliceTokenQuantity;
        transactionCompleteSignals[mintID].user = txInfo.user;

        // get the underlying positions from the slice token
        Position[] memory positions = ISliceToken(msg.sender).getPositions();

        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, positions.length);

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](positions.length);

        for (uint256 i = 0; i < positions.length; i++) {
            // calc amount out
            uint256 _amountOut =
                CrossChainData.calculateAmountOutMin(_sliceTokenQuantity, positions[i].units, positions[i].decimals);
            if (isPositionLocal(positions[i])) {
                IERC20(positions[i].token).safeTransferFrom(txInfo.user, address(this), _amountOut);
                ++transactionCompleteSignals[mintID].signalsOk;
                // We have to record the idx of the successful position
                transactionCompleteSignals[mintID].positionsOkIdxs.push(i);
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: mintID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.MINT,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amountOut,
                    value: 0
                });

                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, i, ccs, positions[i], lzMsgInfo, fees);
            }
        }

        if (checkPendingTransactionCompleteSignals(mintID)) {
            emit UnderlyingAssetsCollected({
                token: msg.sender,
                sliceTokenQuantity: _sliceTokenQuantity,
                owner: txInfo.user
            });
            ISliceToken(msg.sender).mintComplete(mintID);
        }
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 redeemID, uint256[] calldata fees) external payable nonReentrant {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }

        // get redeem tx info
        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getRedeem(redeemID);
        // check that redeem ID exists
        if (txInfo.id != redeemID || txInfo.id == bytes32(0)) {
            revert RedeemIdDoesNotExist();
        }

        // create tx complete signals struct
        transactionCompleteSignals[redeemID].token = msg.sender;
        transactionCompleteSignals[redeemID].user = txInfo.user;
        transactionCompleteSignals[redeemID].sliceTokenQuantity = txInfo.quantity;

        // get the underlying positions of the slice token
        Position[] memory positions = ISliceToken(msg.sender).getPositions();

        uint256 len = positions.length;

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](len);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, len);

        for (uint256 i = 0; i < len; i++) {
            uint256 _amount =
                CrossChainData.calculateAmountOutMin(txInfo.quantity, positions[i].units, positions[i].decimals);
            if (isPositionLocal(positions[i])) {
                IERC20(positions[i].token).safeTransfer(txInfo.user, _amount);
                // increase ready signal after each local transfer
                ++transactionCompleteSignals[redeemID].signalsOk;
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: redeemID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.REDEEM,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amount,
                    value: 0
                });

                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, i, ccs, positions[i], lzMsgInfo, fees);
            }
        }

        // if all signals are in call redeemComplete on token contract
        if (checkPendingTransactionCompleteSignals(redeemID)) {
            emit UnderlyingAssetsRedeemed({token: msg.sender, sliceTokenQuantity: txInfo.quantity, owner: txInfo.user});
            ISliceToken(msg.sender).redeemComplete(redeemID);
        }
    }

    function refund(SliceTransactionInfo calldata txInfo, uint256[] calldata fees) external payable nonReentrant {
        if (!isSliceTokenRegistered(msg.sender)) {
            revert UnregisteredSliceToken();
        }
        // get the tx complete signal info
        TransactionCompleteSignals memory _txCompleteSignal = transactionCompleteSignals[txInfo.id];
        // if state is not REFUNDING revert
        if (txInfo.state != TransactionState.REFUNDING) {
            revert InvalidTransactionState();
        }

        Position[] memory _positions = ISliceToken(_txCompleteSignal.token).getPositions();

        // check that cross-chain signals for all underyling positions have been received - both OK and not OK
        bool _allSignalsReceived = _txCompleteSignal.signalsOk + _txCompleteSignal.signalsFailed == _positions.length;
        if (!_allSignalsReceived) {
            revert NotAllCrossChainSignalsReceived();
        }

        _refund(_txCompleteSignal, txInfo, _positions, fees);

        // check that all the failed transfers have been refunded
        bool _allTransfersRefunded = _txCompleteSignal.signalsOk == refundSignals[txInfo.id];

        // if yes update state to REFUNDED in slice token
        if (_allSignalsReceived && _allTransfersRefunded) {
            ISliceToken(_txCompleteSignal.token).refundComplete(txInfo.id);
        }
    }

    /**
     * @dev See ISliceCore - changeSliceTokenCreationEnabled
     */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external onlyOwner {
        isTokenCreationEnabled = _isEnabled;
    }

    /**
     * @dev See ISliceCore - changeApprovedSliceTokenCreator
     */
    function changeApprovedSliceTokenCreator(address user, bool isApproved) external onlyOwner {
        approvedSliceTokenCreators[user] = isApproved;
    }

    function setLzGas(CrossChainSignalType ccsType, uint128 gas) external onlyOwner {
        lzGasLookup[ccsType] = gas;
    }

    /* =========================================================== */
    /*   =================   EXTERNAL VIEW   ==================    */
    /* =========================================================== */
    /**
     * @dev See ISliceCore - getRegisteredSliceTokensCount
     */
    function getRegisteredSliceTokensCount() external view returns (uint256) {
        return registeredSliceTokensCount;
    }

    /**
     * @dev See ISliceCore - getRegisteredSliceTokens
     */
    function getRegisteredSliceTokens() external view returns (address[] memory) {
        return registeredSliceTokensArray;
    }

    /**
     * @dev See ISliceCore - getRegisteredSliceToken
     */
    function getRegisteredSliceToken(uint256 idx) external view returns (address) {
        return registeredSliceTokensArray[idx];
    }

    /* =========================================================== */
    /*   ==================   PUBLIC VIEW   ===================    */
    /* =========================================================== */
    /**
     * @dev See ISliceCore - canCreateSlice
     */
    function canCreateSlice(address user) public view returns (bool) {
        return approvedSliceTokenCreators[user];
    }

    /**
     * @dev See ISliceCore - isSliceTokenRegistered
     */
    function isSliceTokenRegistered(address token) public view returns (bool) {
        return registeredSliceTokens[token];
    }

    /* =========================================================== */
    /*   ===================    INTERNAL   ====================    */
    /* =========================================================== */
    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32, /* _guid */ // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address, /* _executor */ // the Executor address.
        bytes calldata /* _extraData */ // arbitrary data appended by the Executor
    ) internal override {
        // verify that the msg came from the slice core address
        if (address(uint160(uint256(_origin.sender))) != address(this)) {
            revert OriginNotSliceCore();
        }

        CrossChainSignal[] memory ccs = abi.decode(payload, (CrossChainSignal[]));

        require(msg.value >= ccs[0].value, "Not enough msg value provided");

        // array will always only contain msgs of one type
        CrossChainSignalType ccsType = ccs[0].ccsType;

        if (ccsType == CrossChainSignalType.MINT_COMPLETE) {
            handleMintCompleteSignal(ccs);
        } else if (ccsType == CrossChainSignalType.MINT) {
            handleMintSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REDEEM) {
            handleRedeemSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REDEEM_COMPLETE) {
            handleRedeemCompleteSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REFUND) {
            handleRefundSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REFUND_COMPLETE) {
            handleRefundCompleteSignal(ccs);
        }
    }

    function handleMintCompleteSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs[i].id];

            // verify that the payload status is OK
            if (!ccs[i].success) {
                // update the tx state to failed
                ++transactionCompleteSignals[ccs[i].id].signalsFailed;
                ISliceToken(txCompleteSignals.token).mintFailed(ccs[i].id);
                return;
            }

            // register complete signal
            ++transactionCompleteSignals[ccs[i].id].signalsOk;

            uint256 _posIdx = ISliceToken(txCompleteSignals.token).getPosIdx(ccs[i].underlying);

            // We have to record the idx of the successful position
            transactionCompleteSignals[ccs[i].id].positionsOkIdxs.push(_posIdx);

            if (checkPendingTransactionCompleteSignals(ccs[i].id)) {
                emit UnderlyingAssetsCollected({
                    token: txCompleteSignals.token,
                    sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                    owner: txCompleteSignals.user
                });
                // if all complete signals received: call mintComplete on token
                ISliceToken(txCompleteSignals.token).mintComplete(ccs[i].id);
            }
        }
    }

    function handleMintSignal(CrossChainSignal[] memory ccs) internal {
        // Loop through array, transfer each asset, compose CCS and append to array
        uint256 ccsLength = ccs.length;
        CrossChainSignal[] memory ccsResponses = new CrossChainSignal[](ccsLength);

        for (uint256 i = 0; i < ccsLength; i++) {
            bool success;
            /// @dev on Failed transfers, we don't want to revert the function, because we need to send success = false back to the origin chain
            try IERC20(ccs[i].underlying).transferFrom(ccs[i].user, address(this), ccs[i].units) {
                success = true;
            } catch {}
            // create cross chain signal
            CrossChainSignal memory _ccsResponse = CrossChainSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.MINT_COMPLETE,
                success: success,
                user: ccs[i].user,
                underlying: ccs[i].underlying,
                units: ccs[i].units,
                value: 0
            });

            ccsResponses[i] = _ccsResponse;
        }

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.MINT_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs[0].srcChainId);
        // send LZ message
        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded, ccs[0].user);
    }

    function handleRedeemSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        CrossChainSignal[] memory ccsResponses = new CrossChainSignal[](ccsLength);

        for (uint256 i = 0; i < ccsLength; i++) {
            IERC20(ccs[i].underlying).safeTransfer(ccs[i].user, ccs[i].units);

            // send cross chain success msg
            CrossChainSignal memory _ccsResponse = CrossChainSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REDEEM_COMPLETE,
                success: true,
                user: address(0),
                underlying: address(0),
                units: 0,
                value: 0
            });

            ccsResponses[i] = _ccsResponse;
        }

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs[0].srcChainId);

        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded, ccs[0].user);
    }

    function handleRedeemCompleteSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs[i].id];

            ++transactionCompleteSignals[ccs[i].id].signalsOk;

            if (checkPendingTransactionCompleteSignals(ccs[i].id)) {
                emit UnderlyingAssetsRedeemed({
                    token: txCompleteSignals.token,
                    sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                    owner: txCompleteSignals.user
                });

                ISliceToken(txCompleteSignals.token).redeemComplete(ccs[i].id);
            }
        }
    }

    function handleRefundSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        CrossChainSignal[] memory ccsResponses = new CrossChainSignal[](ccsLength);

        for (uint256 i = 0; i < ccsLength; i++) {
            IERC20(ccs[i].underlying).safeTransfer(ccs[i].user, ccs[i].units);
            CrossChainSignal memory _ccsResponse = CrossChainSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REFUND_COMPLETE,
                success: true,
                user: ccs[i].user,
                underlying: ccs[i].underlying,
                units: ccs[i].units,
                value: 0
            });

            ccsResponses[i] = _ccsResponse;
        }

        // Send cross-chain msg with OK
        bytes memory ccsEncoded = abi.encode(ccsResponses);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REFUND_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs[0].srcChainId);

        // send LZ message
        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded,ccs[0].user);
    }

    function handleRefundCompleteSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            TransactionCompleteSignals memory _txCompleteSignal = transactionCompleteSignals[ccs[i].id];

            // increment refund signals count
            ++refundSignals[ccs[i].id];
            uint256 _numberOfPos = ISliceToken(_txCompleteSignal.token).getNumberOfPositions();
            // check that cross-chain signals for all underyling positions have been received - both OK and not OK
            bool _allSignalsReceived = _txCompleteSignal.signalsOk + _txCompleteSignal.signalsFailed == _numberOfPos;
            // check that all the failed transfers have been refunded
            bool _allTransfersRefunded = _txCompleteSignal.signalsOk == refundSignals[ccs[i].id];
            // if all received call slice token
            // if yes update state to REFUNDED in slice token
            if (_allSignalsReceived && _allTransfersRefunded) {
                ISliceToken(_txCompleteSignal.token).refundComplete(ccs[i].id);
            }
        }
    }

    function groupAndSendLzMsg(
        CrossChainSignal[] memory ccMsgs,
        uint256 currentIdx,
        CrossChainSignal memory ccs,
        Position memory position,
        LzMsgGroupInfo memory lzMsgInfo,
        uint256[] memory fees
    ) internal returns (CrossChainSignal[] memory, LzMsgGroupInfo memory) {
        if (lzMsgInfo.currentChainId == position.chainId) {
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            ++lzMsgInfo.currentCount;
        } else {
            if (lzMsgInfo.currentChainId != 0) {
                {
                    uint256 currentCount = lzMsgInfo.currentCount;
                    assembly {
                        mstore(ccMsgs, currentCount)
                    }
                }
                ccMsgs[0].value = fees[lzMsgInfo.totalMsgCount];
                bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);

                Chain memory dstChain = chainInfo.getChainInfo(lzMsgInfo.currentChainId);

                bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({
                    _gas: lzGasLookup[ccs.ccsType],
                    _value: uint128(fees[lzMsgInfo.totalMsgCount])
                });

                _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsMsgsEncoded, ccs.user);

                lzMsgInfo.currentCount = 0;
                ++lzMsgInfo.totalMsgCount;
                lzMsgInfo.currentChainId = position.chainId;
                ccMsgs = new CrossChainSignal[](lzMsgInfo.positionsLength);
            }

            ccMsgs[lzMsgInfo.currentCount] = ccs;
            lzMsgInfo.currentChainId = position.chainId;
            ++lzMsgInfo.currentCount;
        }
        // if it is the last message and we have a chainId in the array we send the message
        if (currentIdx == lzMsgInfo.positionsLength - 1 && lzMsgInfo.currentCount != 0) {
            {
                uint256 currentCount = lzMsgInfo.currentCount;
                assembly {
                    mstore(ccMsgs, currentCount)
                }
            }
            ccMsgs[0].value = fees[lzMsgInfo.totalMsgCount];
            bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
            Chain memory dstChain = chainInfo.getChainInfo(lzMsgInfo.currentChainId);

            bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({
                _gas: lzGasLookup[ccs.ccsType],
                _value: uint128(fees[lzMsgInfo.totalMsgCount])
            });

            _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsMsgsEncoded, ccs.user);
        }

        return (ccMsgs, lzMsgInfo);
    }

    /* =========================================================== */
    /*   =================   INTERNAL VIEW   ==================    */
    /* =========================================================== */
    function isPositionLocal(Position memory position) internal view returns (bool) {
        return position.chainId == block.chainid;
    }

    // checks the signal count after each swap, in each callback
    function checkPendingTransactionCompleteSignals(bytes32 id) internal view returns (bool) {
        TransactionCompleteSignals memory _transactionCompleteSignal = transactionCompleteSignals[id];
        uint256 _numOfPositions = ISliceToken(_transactionCompleteSignal.token).getNumberOfPositions();
        return _transactionCompleteSignal.signalsOk == _numOfPositions;
    }

    /* =========================================================== */
    /*   ===================    PRIVATE    ====================    */
    /* =========================================================== */
    function _sendLayerZeroMessage(uint32 _lzEndpointId, bytes memory _lzSendOpts, bytes memory _ccsEncoded, address _refundAddress) private {
        MessagingFee memory _fee = _quote(_lzEndpointId, _ccsEncoded, _lzSendOpts, false);

        endpoint.send{value: _fee.nativeFee}(
            MessagingParams(_lzEndpointId, _getPeerOrRevert(_lzEndpointId), _ccsEncoded, _lzSendOpts, false),
            payable(_refundAddress)
        );
    }

    function _refund(
        TransactionCompleteSignals memory _txCompleteSignal,
        SliceTransactionInfo memory _txInfo,
        Position[] memory _positions,
        uint256[] calldata fees
    ) private {
        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](_txCompleteSignal.positionsOkIdxs.length);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, _txCompleteSignal.positionsOkIdxs.length);

        // loop through all the positions that have already been transferred to the contract
        for (uint256 i = 0; i < _txCompleteSignal.positionsOkIdxs.length; i++) {
            uint256 _posIdx = _txCompleteSignal.positionsOkIdxs[i];
            uint256 _amountOut = CrossChainData.calculateAmountOutMin(
                _txInfo.quantity, _positions[_posIdx].units, _positions[i].decimals
            );
            // if it is local, refund back to user
            if (isPositionLocal(_positions[_posIdx])) {
                _refundLocal(_txInfo.id, _positions[_posIdx], _amountOut, _txInfo.user);
            } else {
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _txInfo.id,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.REFUND,
                    success: false,
                    user: _txInfo.user,
                    underlying: _positions[i].token,
                    units: _amountOut,
                    value: 0
                });
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(
                    ccMsgs,
                    i,
                    ccs,
                    _positions[i],
                    lzMsgInfo,
                    fees
                );
            }
        }
    }

    function _refundLocal(bytes32 _mintID, Position memory _position, uint256 _amountOut, address _user) private {
        IERC20(_position.token).safeTransfer(_user, _amountOut);
        ++refundSignals[_mintID];
    }
}
