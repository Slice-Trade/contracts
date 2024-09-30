// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MessagingParams, MessagingReceipt} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {OptionsBuilder} from "@lz-oapp-v2/libs/OptionsBuilder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IChainInfo} from "./interfaces/IChainInfo.sol";
import {ISliceCore} from "./interfaces/ISliceCore.sol";
import {ISliceTokenDeployer} from "./interfaces/ISliceTokenDeployer.sol";

import {TokenAmountUtils} from "./libs/TokenAmountUtils.sol";

import {SliceToken, ISliceToken} from "./SliceToken.sol";

import "./Structs.sol";

/**
 * @author Lajos Deme, Blind Labs
 * @notice The core logic contract of the architecture, provides cross-chain underlying asset management
 */
contract SliceCore is ISliceCore, Ownable2Step, ReentrancyGuard, OApp {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    IChainInfo public immutable chainInfo;

    address public immutable sliceTokenDeployer;

    bool public isTokenCreationEnabled;

    mapping(address creator => bool isApproved) public approvedSliceTokenCreators;
    mapping(CrossChainSignalType ccsType => uint128 gas) public lzGasLookup;

    mapping(address token => bool isRegistered) public registeredSliceTokens;
    address[] public registeredSliceTokensArray;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 id => TransactionCompleteSignals signal) public transactionCompleteSignals;
    mapping(bytes32 id => uint256) refundSignals;

    modifier onlySliceToken() {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }
        _;
    }

    constructor(address _lzEndpoint, address _chainInfo, address _sliceTokenDeployer, address _owner)
        Ownable(_owner)
        OApp(_lzEndpoint, _owner)
    {
        chainInfo = IChainInfo(_chainInfo);
        sliceTokenDeployer = _sliceTokenDeployer;

        lzGasLookup[CrossChainSignalType.MINT] = 3e5;
        lzGasLookup[CrossChainSignalType.REDEEM] = 2.5e5;
        lzGasLookup[CrossChainSignalType.REFUND] = 2.5e5;

        lzGasLookup[CrossChainSignalType.MINT_COMPLETE] = 1.6e5;
        lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE] = 1.6e5;
        lzGasLookup[CrossChainSignalType.REFUND_COMPLETE] = 2e5;
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
    function collectUnderlying(bytes32 mintID, uint128[] calldata fees) external payable nonReentrant onlySliceToken {
        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(mintID);
        if (txInfo.id != mintID || txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        transactionCompleteSignals[mintID].token = msg.sender;
        transactionCompleteSignals[mintID].user = txInfo.user;
        transactionCompleteSignals[mintID].sliceTokenQuantity = txInfo.quantity;

        // get the underlying positions from the slice token
        Position[] memory positions = ISliceToken(msg.sender).getPositions();

        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](positions.length);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, positions.length, msg.value);

        for (uint256 i = 0; i < positions.length; i++) {
            uint256 _amountOut =
                TokenAmountUtils.calculateAmountOutMin(txInfo.quantity, positions[i].units, positions[i].decimals);
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

                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, positions[i], lzMsgInfo, fees);
            }
        }

        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, fees, txInfo.user);
        }

        if (checkPendingTransactionCompleteSignals(mintID)) {
            emit UnderlyingAssetsCollected({token: msg.sender, sliceTokenQuantity: txInfo.quantity, owner: txInfo.user});
            ISliceToken(msg.sender).mintComplete(mintID);
        }
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 redeemID, uint128[] calldata fees) external payable nonReentrant onlySliceToken {
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
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, len, msg.value);

        for (uint256 i = 0; i < len; i++) {
            uint256 _amount =
                TokenAmountUtils.calculateAmountOutMin(txInfo.quantity, positions[i].units, positions[i].decimals);
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

                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, positions[i], lzMsgInfo, fees);
            }
        }

        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, fees, txInfo.user);
        }

        // if all signals are in call redeemComplete on token contract
        if (checkPendingTransactionCompleteSignals(redeemID)) {
            emit UnderlyingAssetsRedeemed({token: msg.sender, sliceTokenQuantity: txInfo.quantity, owner: txInfo.user});
            ISliceToken(msg.sender).redeemComplete(redeemID);
        }
    }

    /**
     * @dev See ISliceCore - refund
     */
    function refund(SliceTransactionInfo calldata txInfo, uint128[] calldata fees)
        external
        payable
        nonReentrant
        onlySliceToken
    {
        // if state is not REFUNDING revert
        if (txInfo.state != TransactionState.REFUNDING) {
            revert InvalidTransactionState();
        }

        // get the tx complete signal info
        TransactionCompleteSignals memory _txCompleteSignal = transactionCompleteSignals[txInfo.id];

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
            emit UnderlyingAssetsRefunded({token: _txCompleteSignal.token, mintId: txInfo.id, owner: txInfo.user});
            ISliceToken(_txCompleteSignal.token).refundComplete(txInfo.id);
        }
    }

    /**
     * @dev See ISliceCore - changeSliceTokenCreationEnabled
     */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external onlyOwner {
        isTokenCreationEnabled = _isEnabled;
        emit ChangedSliceTokenCreationEnabled(_isEnabled);
    }

    /**
     * @dev See ISliceCore - changeApprovedSliceTokenCreator
     */
    function changeApprovedSliceTokenCreator(address user, bool isApproved) external onlyOwner {
        approvedSliceTokenCreators[user] = isApproved;
        emit ChangedApprovedSliceTokenCreator(user, isApproved);
    }

    /**
     * @dev See ISliceCore - setLzBaseGas
     */
    function setLzBaseGas(CrossChainSignalType ccsType, uint128 gas) external onlyOwner {
        lzGasLookup[ccsType] = gas;
        emit SetLzBaseGas(ccsType, gas);
    }

    /**
     * @dev This is a work around to allow using SafeERC20.safeTransferFrom in a try/catch block
     * This is needed because internal functions can not be used in a try/catch block
     * More context here: https://ethereum.stackexchange.com/questions/148855/how-can-we-use-safetransferfrom-function-in-a-try-catch-block
     */
    function attemptTransfer(address token, address from, address to, uint256 amount) external {
        if (msg.sender != address(this)) revert("Only slice core can call");
        IERC20(token).safeTransferFrom(from, to, amount);
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

    /**
     * @dev See ISliceCore - isSliceTokenRegistered
     */
    function isSliceTokenRegistered(address token) external view returns (bool) {
        return registeredSliceTokens[token];
    }

    function getTransactionCompleteSignal(bytes32 id) external view returns (TransactionCompleteSignals memory) {
        return transactionCompleteSignals[id];
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

        if (ccsType == CrossChainSignalType.MINT) {
            handleMintSignal(ccs);
        } else if (ccsType == CrossChainSignalType.MINT_COMPLETE) {
            handleMintCompleteSignal(ccs);
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
                continue;
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
            try this.attemptTransfer(ccs[i].underlying, ccs[i].user, address(this), ccs[i].units) {
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

        _sendLzMsg(CrossChainSignalType.MINT_COMPLETE, ccsEncoded, ccs[0].srcChainId, ccs[0].user);
    }

    function handleRedeemSignal(CrossChainSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        CrossChainSignal[] memory ccsResponses = new CrossChainSignal[](ccsLength);

        for (uint256 i = 0; i < ccsLength; i++) {
            // transfer the asset back to the user
            IERC20(ccs[i].underlying).safeTransfer(ccs[i].user, ccs[i].units);

            // send cross chain success msg
            CrossChainSignal memory _ccsResponse = CrossChainSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REDEEM_COMPLETE,
                success: true,
                user: ccs[i].user,
                underlying: ccs[i].underlying,
                units: ccs[i].units,
                value: 0
            });

            ccsResponses[i] = _ccsResponse;
        }

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        _sendLzMsg(CrossChainSignalType.REDEEM_COMPLETE, ccsEncoded, ccs[0].srcChainId, ccs[0].user);
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
            // transfer the asset back to the user
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

        bytes memory ccsEncoded = abi.encode(ccsResponses);

        _sendLzMsg(CrossChainSignalType.REFUND_COMPLETE, ccsEncoded, ccs[0].srcChainId, ccs[0].user);
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
                emit UnderlyingAssetsRefunded({token: _txCompleteSignal.token, mintId: ccs[i].id, owner: ccs[i].user});
                ISliceToken(_txCompleteSignal.token).refundComplete(ccs[i].id);
            }
        }
    }

    function groupAndSendLzMsg(
        CrossChainSignal[] memory ccMsgs,
        CrossChainSignal memory ccs,
        Position memory position,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees
    ) internal returns (CrossChainSignal[] memory, LzMsgGroupInfo memory) {
        // if it is the same chain id add the message to the list and icrease CCS count
        if (lzMsgInfo.currentChainId == position.chainId) {
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            ++lzMsgInfo.currentCount;
        } else {
            // if it is another chain id, send the previous messages in the list, then reset everything
            if (lzMsgInfo.currentChainId != 0) {
                (ccMsgs, lzMsgInfo) = _sendGroupedLzMsg(ccMsgs, ccs, lzMsgInfo, fees, address(this));

                lzMsgInfo.currentCount = 0;
                lzMsgInfo.currentChainId = position.chainId;
                ccMsgs = new CrossChainSignal[](lzMsgInfo.positionsLength);
            }
            // add the next message to the now empty list
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            lzMsgInfo.currentChainId = position.chainId;
            ++lzMsgInfo.currentCount;
        }
        return (ccMsgs, lzMsgInfo);
    }

    function _sendGroupedLzMsg(
        CrossChainSignal[] memory ccMsgs,
        CrossChainSignal memory ccs,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees,
        address refundAddress
    ) private returns (CrossChainSignal[] memory, LzMsgGroupInfo memory) {
        // reset the length of the array from positions.length to the actual length
        {
            uint256 currentCount = lzMsgInfo.currentCount;
            assembly {
                mstore(ccMsgs, currentCount)
            }
        }
        // set msg value to send cross chain, encode msgs, get the dst chain id
        ccMsgs[0].value = fees[lzMsgInfo.totalMsgCount];
        bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
        Chain memory dstChain = chainInfo.getChainInfo(lzMsgInfo.currentChainId);

        // create lz send opts
        bytes memory _lzSendOpts = _createLzSendOpts({
            _gas: requiredGas(ccs.ccsType, uint128(lzMsgInfo.currentCount)),
            _value: fees[lzMsgInfo.totalMsgCount]
        });

        // send the message, increase the total sent msg count, deuct the sent fee from the total
        MessagingReceipt memory receipt = _lzSend(
            dstChain.lzEndpointId, ccsMsgsEncoded, _lzSendOpts, MessagingFee(lzMsgInfo.providedFee, 0), refundAddress
        );
        ++lzMsgInfo.totalMsgCount;
        lzMsgInfo.providedFee -= receipt.fee.nativeFee;

        return (ccMsgs, lzMsgInfo);
    }

    /* =========================================================== */
    /*   =================   INTERNAL VIEW   ==================    */
    /* =========================================================== */
    function isPositionLocal(Position memory position) internal view returns (bool) {
        return position.chainId == block.chainid;
    }

    // checks if all completed signals are received
    function checkPendingTransactionCompleteSignals(bytes32 id) internal view returns (bool) {
        TransactionCompleteSignals memory _transactionCompleteSignal = transactionCompleteSignals[id];
        uint256 _numOfPositions = ISliceToken(_transactionCompleteSignal.token).getNumberOfPositions();
        return _transactionCompleteSignal.signalsOk == _numOfPositions;
    }

    function requiredGas(CrossChainSignalType ccsType, uint128 msgsLength) internal view returns (uint128) {
        uint128 _baseGas = lzGasLookup[ccsType];
        uint128 _gasStep = gasStep(ccsType);

        uint128 gasRequired = _baseGas + (_gasStep * msgsLength);

        return gasRequired;
    }

    /* =========================================================== */
    /*   =================   INTERNAL PURE   ==================    */
    /* =========================================================== */
    function gasStep(CrossChainSignalType ccsType) internal pure returns (uint128) {
        if (
            ccsType == CrossChainSignalType.MINT || ccsType == CrossChainSignalType.REDEEM
                || ccsType == CrossChainSignalType.REFUND
        ) {
            return 55_000;
        }
        return 37_000;
    }

    /* =========================================================== */
    /*   ===================    PRIVATE    ====================    */
    /* =========================================================== */
    function _refund(
        TransactionCompleteSignals memory _txCompleteSignal,
        SliceTransactionInfo memory _txInfo,
        Position[] memory _positions,
        uint128[] calldata fees
    ) private {
        CrossChainSignal[] memory ccMsgs = new CrossChainSignal[](_txCompleteSignal.positionsOkIdxs.length);
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, _txCompleteSignal.positionsOkIdxs.length, msg.value);

        // loop through all the positions that have already been transferred to the contract
        for (uint256 i = 0; i < _txCompleteSignal.positionsOkIdxs.length; i++) {
            uint256 _posIdx = _txCompleteSignal.positionsOkIdxs[i];
            uint256 _amountOut = TokenAmountUtils.calculateAmountOutMin(
                _txInfo.quantity, _positions[_posIdx].units, _positions[_posIdx].decimals
            );
            // if it is local, refund back to user
            if (isPositionLocal(_positions[_posIdx])) {
                IERC20(_positions[_posIdx].token).safeTransfer(_txInfo.user, _amountOut);
                ++refundSignals[_txInfo.id];
            } else {
                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _txInfo.id,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.REFUND,
                    success: false,
                    user: _txInfo.user,
                    underlying: _positions[_posIdx].token,
                    units: _amountOut,
                    value: 0
                });
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, _positions[_posIdx], lzMsgInfo, fees);
            }
        }
        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, fees, _txInfo.user);
        }
    }

    function _createLzSendOpts(uint128 _gas, uint128 _value) private pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }

    function _sendLzMsg(CrossChainSignalType ccsType, bytes memory ccsEncoded, uint32 srcChainId, address refundAddress)
        private
    {
        bytes memory _lzSendOpts = _createLzSendOpts({_gas: lzGasLookup[ccsType], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(srcChainId);

        _lzSend(srcChain.lzEndpointId, ccsEncoded, _lzSendOpts, MessagingFee(msg.value, 0), refundAddress);
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

    /// @dev Receive is required for LayerZero to refund the fee when the contract is batch sending messages
    receive() external payable {}
}
