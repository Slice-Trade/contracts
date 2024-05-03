// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessagingParams, MessagingReceipt} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRouteProcessor} from "./external/IRouteProcessor.sol";
import {ISushiXSwapV2} from "./external/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "./external/ISushiXSwapV2Adapter.sol";
import {IStargateAdapter} from "./external/IStargateAdapter.sol";

import {IChainInfo} from "./interfaces/IChainInfo.sol";
import {ISliceCore} from "./interfaces/ISliceCore.sol";
import {ISliceTokenDeployer} from "./interfaces/ISliceTokenDeployer.sol";

import {Utils} from "./utils/Utils.sol";

import {CrossChainData} from "./libs/CrossChainData.sol";
import {RouteVerifier} from "./libs/RouteVerifier.sol";

import {SliceToken, ISliceToken} from "./SliceToken.sol";

import "./Structs.sol";

/**
 * @author Lajos Deme, Blind Labs
 * @notice The core logic contract of the architecture, provides cross-chain underlying asset management
 */
contract SliceCore is ISliceCore, Ownable, OApp, ReentrancyGuard {
    address public immutable paymentToken;

    ISushiXSwapV2 public immutable sushiXSwap;

    address public immutable stargateAdapter;
    address public immutable axelarAdapter;

    IChainInfo public immutable chainInfo;

    address public immutable sliceTokenDeployer;

    bool public isTokenCreationEnabled;

    mapping(address creator => bool isApproved) public approvedSliceTokenCreators;

    mapping(address token => bool isRegistered) public registeredSliceTokens;
    address[] public registeredSliceTokensArray;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 id => TransactionCompleteSignals signal) public transactionCompleteSignals;

    CrossChainGas public crossChainGas = CrossChainGas(550000, 500000);

    mapping(CrossChainSignalType ccsType => uint128 gas) public lzGasLookup;

    constructor(
        address _paymentToken,
        address _sushiXSwap,
        address _stargateAdapter,
        address _axelarAdapter,
        address _lzEndpoint,
        address _chainInfo,
        address _sliceTokenDeployer,
        address _owner
    ) Ownable(_owner) OApp(_lzEndpoint, _owner) {
        paymentToken = _paymentToken;
        sushiXSwap = ISushiXSwapV2(_sushiXSwap);
        chainInfo = IChainInfo(_chainInfo);
        stargateAdapter = _stargateAdapter;
        axelarAdapter = _axelarAdapter;
        sliceTokenDeployer = _sliceTokenDeployer;

        lzGasLookup[CrossChainSignalType.MINT] = 120000;
        lzGasLookup[CrossChainSignalType.REDEEM] = 200000;
        lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE] = 150000;
        lzGasLookup[CrossChainSignalType.MANUAL_MINT] = 200000;
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
            paymentToken: paymentToken,
            core: address(this)
        });

        registeredSliceTokens[token] = true;
        registeredSliceTokensArray.push(token);
        ++registeredSliceTokensCount;

        emit SliceTokenCreated(token);

        return token;
    }

    /**
     * @dev See ISliceCore - purchaseUnderlyingAssets
     */
    function purchaseUnderlyingAssets(
        bytes32 _mintID,
        uint256 _sliceTokenQuantity,
        uint256[] memory _maxEstimatedPrices,
        bytes[] memory _routes
    ) external payable nonReentrant {
        // check that slice token (msg.sender) is registered
        if (!registeredSliceTokens[msg.sender]) {
            revert UnregisteredSliceToken();
        }

        if (IERC20(paymentToken).balanceOf(address(this)) < Utils.sumMaxEstimatedPrices(_maxEstimatedPrices)) {
            revert TokenPriceNotTransferred();
        }

        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(_mintID);
        if (txInfo.id != _mintID || txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        transactionCompleteSignals[_mintID].token = msg.sender;
        transactionCompleteSignals[_mintID].sliceTokenQuantity = _sliceTokenQuantity;
        transactionCompleteSignals[_mintID].user = txInfo.user;

        // get the underlying positions from the slice token
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        uint256 len = positions.length;
        for (uint256 i = 0; i < len; i++) {
            if (isPositionLocal(positions[i])) {
                // if asset is local execute swap right away: (check block.chainid)
                bool success = executeLocalSwap(_sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], _routes[i]);
                if (!success) {
                    revert LocalSwapFailed();
                }
                // increase the ready signal after each local swap
                ++transactionCompleteSignals[_mintID].signals;
            } else {
                executeCrossChainSwap(
                    _mintID, _sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], txInfo, _routes[i]
                );
            }
        }

        // if all signals are in -> call mintComplete on token contract
        if (checkPendingTransactionCompleteSignals(_mintID)) {
            emit UnderlyingAssetsProcured({
                token: msg.sender,
                sliceTokenQuantity: _sliceTokenQuantity,
                owner: txInfo.user
            });
            SliceToken(msg.sender).mintComplete(_mintID);
        }
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
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        uint256 len = positions.length;
        for (uint256 i = 0; i < len; i++) {
            // calc amount out
            uint256 _amountOut = CrossChainData.calculateAmountOutMin(_sliceTokenQuantity, positions[i].units);
            if (isPositionLocal(positions[i])) {
                // transfer
                bool success = IERC20(positions[i].token).transferFrom(txInfo.user, address(this), _amountOut);
                if (!success) {
                    revert LocalAssetTransferFailed();
                }
                ++transactionCompleteSignals[_mintID].signals;
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                Chain memory dstChain = chainInfo.getChainInfo(positions[i].chainId);

                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _mintID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.MANUAL_MINT,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amountOut
                });

                bytes memory ccsEncoded = abi.encode(ccs);

                bytes memory _lzSendOpts =
                    CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.MANUAL_MINT], _value: 0});

                _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsEncoded);
            }
        }

        if (checkPendingTransactionCompleteSignals(_mintID)) {
            emit UnderlyingAssetsProcured({
                token: msg.sender,
                sliceTokenQuantity: _sliceTokenQuantity,
                owner: txInfo.user
            });
            SliceToken(msg.sender).mintComplete(_mintID);
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

        // get the underlying positions of the slice token
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        uint256 len = positions.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 _amount = CrossChainData.calculateAmountOutMin(txInfo.quantity, positions[i].units);
            if (isPositionLocal(positions[i])) {
                // if the asset is local execute the transfer right away
                bool success = IERC20(positions[i].token).transfer(txInfo.user, _amount);
                if (!success) {
                    revert UnderlyingAssetTransferFailed();
                }
                // increase ready signal after each local transfer
                ++transactionCompleteSignals[_redeemID].signals;
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                Chain memory dstChain = chainInfo.getChainInfo(positions[i].chainId);

                CrossChainSignal memory ccs = CrossChainSignal({
                    id: _redeemID,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.REDEEM,
                    success: false,
                    user: txInfo.user,
                    underlying: positions[i].token,
                    units: _amount
                });

                bytes memory ccsEncoded = abi.encode(ccs);

                bytes memory _lzSendOpts =
                    CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REDEEM], _value: 0});

                _sendLayerZeroMessage(dstChain.lzEndpointId, _lzSendOpts, ccsEncoded);
            }
        }

        // if all signals are in call redeemComplete on token contract
        if (checkPendingTransactionCompleteSignals(_redeemID)) {
            emit UnderlyingAssetsRedeemed({token: msg.sender, sliceTokenQuantity: txInfo.quantity, owner: txInfo.user});
            SliceToken(msg.sender).redeemComplete(_redeemID);
        }
    }

    /**
     * @dev See IPayloadExecutor - onPayloadReceive
     */
    function onPayloadReceive(bytes memory _data) external payable {
        // implement on payload receive, verify the transfer details on dst chain
        if (msg.sender != stargateAdapter) {
            revert OnlyStargateAdapterCanCall();
        }

        SlicePayloadData memory payloadData = abi.decode(_data, (SlicePayloadData));
        uint256 balance = IERC20(payloadData.tokenOut).balanceOf(address(this));
        if (balance < payloadData.amountOutMin) {
            revert IncorrectAmountOut();
        }

        // implement layer zero msg send to main chain contract
        // get src lz chain id from payload data
        Chain memory srcChain = chainInfo.getChainInfo(payloadData.srcChainId);
        // create cross chain signal
        CrossChainSignal memory ccs = CrossChainSignal({
            id: payloadData.mintID,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: true,
            user: address(0),
            underlying: address(0),
            units: 0
        });
        // encode to bytes
        bytes memory ccsEncoded = abi.encode(ccs);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.MINT], _value: 0});

        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success);
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

    function setCrossChainGas(CrossChainGas memory _crossChainGas) external onlyOwner {
        crossChainGas = _crossChainGas;
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
        // verify that it was sent by the correct layer zero endpoint
        if (msg.sender != address(endpoint)) {
            revert OnlyLzEndpointCanCall();
        }

        // verify that the msg came from the slice core address
        if (address(uint160(uint256(_origin.sender))) != address(this)) {
            revert OriginNotSliceCore();
        }

        CrossChainSignal memory ccs = abi.decode(payload, (CrossChainSignal));

        if (ccs.ccsType == CrossChainSignalType.MINT) {
            handleUnderlyingProcureCompleteSignal(ccs);
        } else if (ccs.ccsType == CrossChainSignalType.MANUAL_MINT) {
            handleManualMintSignal(ccs);
        } else if (ccs.ccsType == CrossChainSignalType.REDEEM) {
            handleRedeemSignal(ccs);
        } else if (ccs.ccsType == CrossChainSignalType.REDEEM_COMPLETE) {
            handleRedeemCompleteSignal(ccs);
        }
    }

    function handleUnderlyingProcureCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];
        // verify that the mint id from the payload exists
        if (!isSliceTokenRegistered(txCompleteSignals.token)) {
            revert UnregisteredSliceToken();
        }

        // verify that the payload status is OK
        if (!ccs.success) {
            revert CrossChainSwapFailed(); // TODO: Refund logic here
        }

        // then register complete signal
        ++transactionCompleteSignals[ccs.id].signals;

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsProcured({
                token: txCompleteSignals.token,
                sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                owner: txCompleteSignals.user
            });
            // if all complete signals received: call mintComplete on token
            SliceToken(txCompleteSignals.token).mintComplete(ccs.id);
        }
    }

    function handleManualMintSignal(CrossChainSignal memory ccs) internal {
        // transfer the given amount of the given token from given user to core
        bool success = IERC20(ccs.underlying).transferFrom(ccs.user, address(this), ccs.units);

        // create cross chain signal
        CrossChainSignal memory _ccsResponse = CrossChainSignal({
            id: ccs.id,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: success,
            user: ccs.user,
            underlying: ccs.underlying,
            units: ccs.units
        });

        bytes memory ccsEncoded = abi.encode(_ccsResponse);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.MINT], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs.srcChainId);

        // send LZ message
        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function handleRedeemSignal(CrossChainSignal memory ccs) internal {
        bool success = IERC20(ccs.underlying).transfer(ccs.user, ccs.units);
        if (!success) {
            revert CrossChainRedeemFailed();
        }

        // send cross chain success msg
        CrossChainSignal memory _ccsResponse = CrossChainSignal({
            id: ccs.id,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REDEEM_COMPLETE,
            success: true,
            user: address(0),
            underlying: address(0),
            units: 0
        });

        bytes memory ccsEncoded = abi.encode(_ccsResponse);

        bytes memory _lzSendOpts =
            CrossChainData.createLzSendOpts({_gas: lzGasLookup[CrossChainSignalType.REDEEM_COMPLETE], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(ccs.srcChainId);

        _sendLayerZeroMessage(srcChain.lzEndpointId, _lzSendOpts, ccsEncoded);
    }

    function handleRedeemCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];

        if (!isSliceTokenRegistered(txCompleteSignals.token)) {
            revert UnregisteredSliceToken();
        }

        // verify that the payload status is OK
        if (!ccs.success) {
            revert CrossChainRedeemFailed();
        }

        ++transactionCompleteSignals[ccs.id].signals;

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsRedeemed({
                token: txCompleteSignals.token,
                sliceTokenQuantity: txCompleteSignals.sliceTokenQuantity,
                owner: txCompleteSignals.user
            });

            SliceToken(txCompleteSignals.token).redeemComplete(ccs.id);
        }
    }

    function executeLocalSwap(
        uint256 _sliceTokenQuantity,
        uint256 _maxEstimatedPrice,
        Position memory _position,
        bytes memory _route
    ) internal returns (bool) {
        RouteVerifier.verifyRoute(address(this), _route);

        IERC20(paymentToken).approve(address(sushiXSwap), _maxEstimatedPrice);

        uint256 amountIn = _maxEstimatedPrice;
        uint256 amountOutMin = CrossChainData.calculateAmountOutMin(_sliceTokenQuantity, _position.units);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: paymentToken,
            amountIn: amountIn,
            tokenOut: _position.token,
            amountOutMin: amountOutMin,
            to: address(this),
            route: _route
        });

        bytes memory rpd_encoded = abi.encode(rpd);

        sushiXSwap.swap(rpd_encoded);

        uint256 balanceAfterSwap = IERC20(_position.token).balanceOf(address(this));
        return balanceAfterSwap >= _position.units;
    }

    // TODO: get fees from both axelar and stargate, compare them and go with the lowest fee bridge
    function executeCrossChainSwap(
        bytes32 _mintId,
        uint256 _sliceTokenQuantity,
        uint256 _maxEstimatedPrice,
        Position memory _position,
        SliceTransactionInfo memory _txInfo,
        bytes memory _route
    ) internal {
        RouteVerifier.verifyRoute(address(this), _route);

        IERC20(paymentToken).approve(address(sushiXSwap), _maxEstimatedPrice);

        uint256 amountOutMin = CrossChainData.calculateAmountOutMin(_sliceTokenQuantity, _position.units);

        Chain memory dstChain = chainInfo.getChainInfo(_position.chainId);

        bytes memory rpd_encoded_dst = CrossChainData.createRouteProcessorDataEncoded(
            dstChain, _position.token, amountOutMin, address(this), _route
        );

        bytes memory payloadDataEncoded = CrossChainData.createPayloadDataEncoded(
            _mintId, _position.token, amountOutMin, address(this), crossChainGas.gasForPayload, _txInfo.data
        );

        sushiXSwap.bridge{
            value: CrossChainData.getGasNeeded(
                dstChain.stargateChainId, stargateAdapter, address(this), rpd_encoded_dst, payloadDataEncoded
                )
        }(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: stargateAdapter,
                tokenIn: paymentToken,
                amountIn: _maxEstimatedPrice,
                to: address(this),
                adapterData: createAdapterData(dstChain, _maxEstimatedPrice, crossChainGas.gasForAdapter)
            }), // bridge params
            _txInfo.user, // refund address
            rpd_encoded_dst, // swap data
            payloadDataEncoded // payload data
        );
    }

    /* =========================================================== */
    /*   =================   INTERNAL VIEW   ==================    */
    /* =========================================================== */
    function isPositionLocal(Position memory _position) internal view returns (bool) {
        return _position.chainId == block.chainid;
    }

    function createAdapterData(Chain memory _dstChain, uint256 _maxEstimatedPrice, uint256 gasForSwap)
        internal
        view
        returns (bytes memory _adapterData)
    {
        _adapterData = abi.encode(
            _dstChain.stargateChainId, // dst chain stargate id
            paymentToken, // token in
            1, // src pool id - USDC
            1, // dst pool id - USDC
            _maxEstimatedPrice, // amount,
            0, // amountMin,
            0, // dust
            _dstChain.stargateAdapter, // receiver
            address(this), // to
            gasForSwap // gas
        );
    }

    // checks the signal count after each swap, in each callback
    function checkPendingTransactionCompleteSignals(bytes32 _id) internal view returns (bool) {
        TransactionCompleteSignals memory _transactionCompleteSignal = transactionCompleteSignals[_id];
        uint256 _numOfPositions = ISliceToken(_transactionCompleteSignal.token).getNumberOfPositions();
        return _transactionCompleteSignal.signals == _numOfPositions;
    }

    /* =========================================================== */
    /*   ===================    PRIVATE    ====================    */
    /* =========================================================== */
    function _sendLayerZeroMessage(uint32 _lzEndpointId, bytes memory _lzSendOpts, bytes memory _ccsEncoded) private {
        MessagingFee memory _fee = _quote(_lzEndpointId, _ccsEncoded, _lzSendOpts, false);

        MessagingReceipt memory _receipt = endpoint.send{value: _fee.nativeFee}(
            MessagingParams(_lzEndpointId, _getPeerOrRevert(_lzEndpointId), _ccsEncoded, _lzSendOpts, false),
            payable(address(this))
        );

        if (_receipt.guid == bytes32(0)) {
            revert LayerZeroSendFailed();
        }
    }
}
