// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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

import {Utils} from "./utils/Utils.sol";

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

    receive() external payable {}

    /* =========================================================== */
    /*   ===================    EXTERNAL   ====================    */
    /* =========================================================== */
    /**
     * @dev See ISliceCore - createSlice
     */
    function createSlice(string calldata _name, string calldata _symbol, Position[] calldata _positions)
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
            name: _name,
            symbol: _symbol,
            positions: _positions,
            core: address(this)
        });

        registeredSliceTokens[token] = true;
        registeredSliceTokensArray.push(token);
        ++registeredSliceTokensCount;

        emit SliceTokenCreated(token);

        return token;
    }

    /**
     * @dev See ISliceCore - collectUnderlyingAssets
     */
    function collectUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity) external payable nonReentrant {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }

        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(_mintID);
        if (txInfo.id != _mintID || txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        transactionCompleteSignals[_mintID].token = msg.sender;
        transactionCompleteSignals[_mintID].sliceTokenQuantity = _sliceTokenQuantity;
        transactionCompleteSignals[_mintID].user = txInfo.user;

        // get the underlying positions from the slice token
        Position[] memory positions = ISliceToken(msg.sender).getPositions();

        uint256 len = positions.length;

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](len);
        uint256 currentChainId;
        uint256 currentCount;

        for (uint256 i = 0; i < len; i++) {
            // calc amount out
            uint256 _amountOut = CrossChainData.calculateAmountOutMin(_sliceTokenQuantity, positions[i].units);
            if (isPositionLocal(positions[i])) { // y
                IERC20(positions[i].token).safeTransferFrom(txInfo.user, address(this), _amountOut);
                ++transactionCompleteSignals[_mintID].signalsOk;
                // We have to record the idx of the successful position
                transactionCompleteSignals[_mintID].positionsOkIdxs.push(i);
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _mintID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.MINT,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amountOut
                });

                (ccMsgs, currentChainId, currentCount) = groupAndSendLzMsg(
                    ccMsgs, currentChainId, currentCount, i, len, CrossChainSignalType.MINT, ccs, positions[i]
                );
            }
        }

        if (checkPendingTransactionCompleteSignals(_mintID)) { // y
            emit UnderlyingAssetsProcured({
                token: msg.sender,
                sliceTokenQuantity: _sliceTokenQuantity,
                owner: txInfo.user
            });
            ISliceToken(msg.sender).mintComplete(_mintID);
        }
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 _redeemID) external payable nonReentrant {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }

        // get redeem tx info
        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getRedeem(_redeemID);
        // check that redeem ID exists
        if (txInfo.id != _redeemID || txInfo.id == bytes32(0)) {
            revert RedeemIdDoesNotExist();
        }

        // create tx complete signals struct
        transactionCompleteSignals[_redeemID].token = msg.sender;
        transactionCompleteSignals[_redeemID].user = txInfo.user;
        transactionCompleteSignals[_redeemID].sliceTokenQuantity = txInfo.quantity;

        // get the underlying positions of the slice token
        Position[] memory positions = ISliceToken(msg.sender).getPositions();

        uint256 len = positions.length;

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](len);
        uint256 currentChainId;
        uint256 currentCount;

        for (uint256 i = 0; i < len; i++) {
            uint256 _amount = CrossChainData.calculateAmountOutMin(txInfo.quantity, positions[i].units);
            if (isPositionLocal(positions[i])) { // y
                IERC20(positions[i].token).safeTransfer(txInfo.user, _amount);
                // increase ready signal after each local transfer
                ++transactionCompleteSignals[_redeemID].signalsOk;
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _redeemID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.REDEEM,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amount
                });

                (ccMsgs, currentChainId, currentCount) = groupAndSendLzMsg(
                    ccMsgs, currentChainId, currentCount, i, len, CrossChainSignalType.REDEEM, ccs, positions[i]
                );
            }
        }

        // if all signals are in call redeemComplete on token contract
        if (checkPendingTransactionCompleteSignals(_redeemID)) { // y
            emit UnderlyingAssetsRedeemed({token: msg.sender, sliceTokenQuantity: txInfo.quantity, owner: txInfo.user});
            ISliceToken(msg.sender).redeemComplete(_redeemID);
        }
    }

    function refund(SliceTransactionInfo memory _txInfo) external payable nonReentrant {
        if (!isSliceTokenRegistered(msg.sender)) {
            revert UnregisteredSliceToken();
        }
        // get the tx complete signal info
        TransactionCompleteSignals memory _txCompleteSignal = transactionCompleteSignals[_txInfo.id];
        // if state is not REFUNDING revert
        if (_txInfo.state != TransactionState.REFUNDING) {
            revert InvalidTransactionState();
        }

        Position[] memory _positions = ISliceToken(_txCompleteSignal.token).getPositions();

        // check that cross-chain signals for all underyling positions have been received - both OK and not OK
        bool _allSignalsReceived = _txCompleteSignal.signalsOk + _txCompleteSignal.signalsFailed == _positions.length;
        if (!_allSignalsReceived) {
            revert NotAllCrossChainSignalsReceived();
        }

        // loop through all the positions that have already been transferred to the contract
        for (uint256 i = 0; i < _txCompleteSignal.positionsOkIdxs.length; i++) {
            uint256 _posIdx = _txCompleteSignal.positionsOkIdxs[i];
            uint256 _amountOut = CrossChainData.calculateAmountOutMin(_txInfo.quantity, _positions[_posIdx].units);
            // if it is local, refund back to user
            if (isPositionLocal(_positions[_posIdx])) { // y
                _refundLocal(_txInfo.id, _positions[_posIdx], _amountOut, _txInfo.user);
            } else {
                // if it is not local send cross chain msg
                _refundCrossChain(_txInfo.id, _positions[_posIdx], _amountOut, _txInfo.user);
            }
        }

        // check that all the failed transfers have been refunded
        bool _allTransfersRefunded = _txCompleteSignal.signalsOk == refundSignals[_txInfo.id];

        // if yes update state to REFUNDED in slice token
        if (_allSignalsReceived && _allTransfersRefunded) { // y
            ISliceToken(_txCompleteSignal.token).refundComplete(_txInfo.id);
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
    function changeApprovedSliceTokenCreator(address _user, bool _isApproved) external onlyOwner {
        approvedSliceTokenCreators[_user] = _isApproved;
    }

    function setLzGas(CrossChainSignalType _ccsType, uint128 _gas) external onlyOwner {
        lzGasLookup[_ccsType] = _gas;
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
    function getRegisteredSliceToken(uint256 _idx) external view returns (address) {
        return registeredSliceTokensArray[_idx];
    }

    /* =========================================================== */
    /*   ==================   PUBLIC VIEW   ===================    */
    /* =========================================================== */
    /**
     * @dev See ISliceCore - canCreateSlice
     */
    function canCreateSlice(address _user) public view returns (bool) {
        return approvedSliceTokenCreators[_user];
    }

    /**
     * @dev See ISliceCore - isSliceTokenRegistered
     */
    function isSliceTokenRegistered(address _token) public view returns (bool) {
        return registeredSliceTokens[_token];
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
        // array will always only contain msgs of one type
        CrossChainSignalType ccsType = ccs[0].ccsType;

        if (ccsType == CrossChainSignalType.MINT_COMPLETE) {
            for (uint256 i = 0; i < ccs.length; i++) {
                handleMintCompleteSignal(ccs[i]);
            }
        } else if (ccsType == CrossChainSignalType.MINT) {
            handleMintSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REDEEM) {
            handleRedeemSignal(ccs);
        } else if (ccsType == CrossChainSignalType.REDEEM_COMPLETE) {
            for (uint256 i = 0; i < ccs.length; i++) {
                handleRedeemCompleteSignal(ccs[i]);
            }
        } else if (ccsType == CrossChainSignalType.REFUND) {
            handleRefundSignal(ccs[0]);
        } else if (ccsType == CrossChainSignalType.REFUND_COMPLETE) {
            handleRefundCompleteSignal(ccs[0]);
        }
    }

    function handleMintCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];

        // verify that the payload status is OK
        if (!ccs.success) {
            // update the tx state to failed
            ++transactionCompleteSignals[ccs.id].signalsFailed;
            ISliceToken(txCompleteSignals.token).mintFailed(ccs.id);
            return;
        }

        // register complete signal
        ++transactionCompleteSignals[ccs.id].signalsOk;

        uint256 _posIdx = ISliceToken(txCompleteSignals.token).getPosIdx(ccs.underlying);

        // We have to record the idx of the successful position
        transactionCompleteSignals[ccs.id].positionsOkIdxs.push(_posIdx);

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsProcured({
                token: txCompleteSignals.token,
                sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                owner: txCompleteSignals.user
            });
            // if all complete signals received: call mintComplete on token
            ISliceToken(txCompleteSignals.token).mintComplete(ccs.id);
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
                units: ccs[i].units
            });

            ccsResponses[i] = _ccsResponse;
        }

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.MINT_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs[0].srcChainId);
        // send LZ message
        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function handleRedeemSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        CrossChainSignal[] memory ccsResponses = new CrossChainSignal[](ccsLength);

        for (uint256 i = 0; i < ccsLength; i++) {
            // TODO: add a check to see if ID is already handled or not
            IERC20(ccs[i].underlying).safeTransfer(ccs[i].user, ccs[i].units);

            // send cross chain success msg
            CrossChainSignal memory _ccsResponse = CrossChainSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REDEEM_COMPLETE,
                success: true,
                user: address(0),
                underlying: address(0),
                units: 0
            });

            ccsResponses[i] = _ccsResponse;
        }

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs[0].srcChainId);

        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function handleRedeemCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];

        ++transactionCompleteSignals[ccs.id].signalsOk;

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsRedeemed({
                token: txCompleteSignals.token,
                sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                owner: txCompleteSignals.user
            });

            ISliceToken(txCompleteSignals.token).redeemComplete(ccs.id);
        }
    }

    function handleRefundSignal(CrossChainSignal memory ccs) internal {
        // TODO: add a check to see if ID is already handled or not
        IERC20(ccs.underlying).safeTransfer(ccs.user, ccs.units);

        CrossChainSignal memory _ccsResponse = CrossChainSignal({
            id: ccs.id,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REFUND_COMPLETE,
            success: true,
            user: ccs.user,
            underlying: ccs.underlying,
            units: ccs.units
        });
        CrossChainSignal[] memory ccsArray = new CrossChainSignal[](1);
        ccsArray[0] = _ccsResponse;

        // Send cross-chain msg with OK
        bytes memory ccsEncoded = abi.encode(ccsArray);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REFUND_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs.srcChainId);

        // send LZ message
        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function handleRefundCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory _txCompleteSignal = transactionCompleteSignals[ccs.id];

        // increment refund signals count
        ++refundSignals[ccs.id];

        uint256 _numberOfPos = ISliceToken(_txCompleteSignal.token).getNumberOfPositions();
        // check that cross-chain signals for all underyling positions have been received - both OK and not OK
        bool _allSignalsReceived = _txCompleteSignal.signalsOk + _txCompleteSignal.signalsFailed == _numberOfPos;
        // check that all the failed transfers have been refunded
        bool _allTransfersRefunded = _txCompleteSignal.signalsOk == refundSignals[ccs.id];

        // if all received call slice token
        // if yes update state to REFUNDED in slice token
        if (_allSignalsReceived && _allTransfersRefunded) {
            ISliceToken(_txCompleteSignal.token).refundComplete(ccs.id);
        }
    }

    function groupAndSendLzMsg(
        CrossChainSignal[] memory ccMsgs,
        uint256 currentChainId,
        uint256 currentCount,
        uint256 currentIdx,
        uint256 positionsLength,
        CrossChainSignalType ccsType,
        CrossChainSignal memory ccs,
        Position memory position
    ) internal returns (CrossChainSignal[] memory, uint256, uint256) {
        if (currentChainId == position.chainId) {
            ccMsgs[currentCount] = ccs;
            ++currentCount;
        } else {
            if (currentChainId != 0) {
                assembly {
                    mstore(ccMsgs, currentCount)
                }
                bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);

                Chain memory dstChain = chainInfo.getChainInfo(currentChainId);

                bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({_gas: lzGasLookup[ccsType], _value: 0});

                _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsMsgsEncoded);

                currentCount = 0;
                currentChainId = position.chainId;
                ccMsgs = new CrossChainSignal[](positionsLength);
            }

            ccMsgs[currentCount] = ccs;
            currentChainId = position.chainId;
            ++currentCount;
        }
        // if it is the last message and we have a chainId in the array we send the message
        if (currentIdx == positionsLength - 1 && currentCount != 0) {
            assembly {
                mstore(ccMsgs, currentCount)
            }
            bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
            Chain memory dstChain = chainInfo.getChainInfo(currentChainId);

            bytes memory _lzSendOpts = CrossChainData.createLzSendOpts({_gas: lzGasLookup[ccsType], _value: 0});

            _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsMsgsEncoded);
        }

        return (ccMsgs, currentChainId, currentCount);
    }

    /* =========================================================== */
    /*   =================   INTERNAL VIEW   ==================    */
    /* =========================================================== */
    function isPositionLocal(Position memory _position) internal view returns (bool) {
        return _position.chainId == block.chainid;
    }

    // checks the signal count after each swap, in each callback
    function checkPendingTransactionCompleteSignals(bytes32 _id) internal view returns (bool) {
        TransactionCompleteSignals memory _transactionCompleteSignal = transactionCompleteSignals[_id];
        uint256 _numOfPositions = ISliceToken(_transactionCompleteSignal.token).getNumberOfPositions();
        return _transactionCompleteSignal.signalsOk == _numOfPositions;
    }

    /* =========================================================== */
    /*   ===================    PRIVATE    ====================    */
    /* =========================================================== */
    function _sendLayerZeroMessage(uint32 _lzEndpointId, bytes memory _lzSendOpts, bytes memory _ccsEncoded) private {
        MessagingFee memory _fee = _quote(_lzEndpointId, _ccsEncoded, _lzSendOpts, false);

        //_lzSend(_lzEndpointId, _ccsEncoded, _lzSendOpts, _fee, payable(address(this)));
        endpoint.send{value: _fee.nativeFee}(
            MessagingParams(_lzEndpointId, _getPeerOrRevert(_lzEndpointId), _ccsEncoded, _lzSendOpts, false),
            payable(address(this))
        );
    }

    function _refundLocal(bytes32 _mintID, Position memory _position, uint256 _amountOut, address _user) private {
        IERC20(_position.token).safeTransfer(_user, _amountOut);
        ++refundSignals[_mintID];
    }

    function _refundCrossChain(bytes32 _mintID, Position memory _position, uint256 _amountOut, address _user) private {
        Chain memory dstChain = chainInfo.getChainInfo(_position.chainId);
        CrossChainSignal memory ccs = CrossChainSignal({
            id: _mintID,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REFUND,
            success: false,
            user: _user,
            underlying: _position.token,
            units: _amountOut
        });

        CrossChainSignal[] memory ccsArray = new CrossChainSignal[](1);
        ccsArray[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsArray);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REFUND], _value: 0});

        _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }
}
