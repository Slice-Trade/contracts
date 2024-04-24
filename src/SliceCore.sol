// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {MessagingParams} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import "./external/ISushiXSwapV2.sol";
import "./external/IRouteProcessor.sol";
import "./external/IStargateAdapter.sol";
import "./external/ISushiXSwapV2Adapter.sol";
import "./interfaces/ISliceCore.sol";
import "./utils/Utils.sol";
import "./interfaces/IChainInfo.sol";
import "./interfaces/ISliceTokenDeployer.sol";
import "./SliceToken.sol";

import "./libs/RouteVerifier.sol";
import "./libs/CrossChainData.sol";

contract SliceCore is ISliceCore, Ownable, OApp {
    address public paymentToken;

    ISushiXSwapV2 public sushiXSwap;

    address public stargateAdapter;
    address public axelarAdapter;

    IChainInfo public chainInfo;

    mapping(address => bool) public approvedSliceTokenCreators;

    bool public isTokenCreationEnabled;

    mapping(address => bool) public registeredSliceTokens;
    address[] public registeredSliceTokensArray;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 => TransactionCompleteSignals) public transactionCompleteSignals;

    CrossChainGas public crossChainGas = CrossChainGas(500000, 280000);

    address public sliceTokenDeployer;

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
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success);
    }

    /**
     * @dev See ISliceCore - createSlice
     */
    function createSlice(string calldata _name, string calldata _symbol, Position[] calldata _positions)
        external
        returns (address)
    {
        require(canCreateSlice(msg.sender), "SliceCore: Unauthorized caller");
        require(isTokenCreationEnabled, "SliceCore: Slice token creation disabled");

        address token = ISliceTokenDeployer(sliceTokenDeployer).deploySliceToken(
            _name, _symbol, _positions, paymentToken, address(this)
        );

        registeredSliceTokens[token] = true;
        registeredSliceTokensArray.push(token);
        registeredSliceTokensCount++;

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
    ) external payable {
        // check that slice token (msg.sender) is registered
        require(registeredSliceTokens[msg.sender], "SliceCore: Only registered Slice token can call");

        require(
            IERC20(paymentToken).balanceOf(address(this)) >= Utils.sumMaxEstimatedPrices(_maxEstimatedPrices),
            "SliceCore: Max estimated price not transferred to contract"
        );

        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(_mintID);
        require(txInfo.id == _mintID, "SliceCore: Mint ID does not exist");

        transactionCompleteSignals[_mintID].token = msg.sender;
        transactionCompleteSignals[_mintID].sliceTokenQuantity = _sliceTokenQuantity;
        transactionCompleteSignals[_mintID].user = txInfo.user;

        // get the underlying positions from the slice token
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        for (uint256 i = 0; i < positions.length; i++) {
            // if asset is local execute swap right away: (check block.chainid)
            if (isPositionLocal(positions[i])) {
                bool success = executeLocalSwap(_sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], _routes[i]);
                require(success, "SliceCore: Local swap failed");
                // increase the ready signal after each local swap
                transactionCompleteSignals[_mintID].signals++;
            } else {
                executeCrossChainSwap(
                    _mintID, _sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], txInfo, _routes[i]
                );
            }
        }

        // if all signals are in -> call mintComplete on token contract
        if (checkPendingTransactionCompleteSignals(_mintID)) {
            emit UnderlyingAssetsPurchased(msg.sender, _sliceTokenQuantity, txInfo.user);
            SliceToken(msg.sender).mintComplete(_mintID);
        }
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 _redeemID) external payable {
        // check that slice token (msg.sender) is registered
        require(registeredSliceTokens[msg.sender], "SliceCore: Only registered Slice token can call");

        // get redeem tx info
        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getRedeem(_redeemID);
        // check that redeem ID exists
        require(txInfo.id == _redeemID, "SliceCore: Redeem ID does not exist");

        // create tx complete signals struct
        transactionCompleteSignals[_redeemID].token = msg.sender;
        transactionCompleteSignals[_redeemID].user = txInfo.user;

        // get the underlying positions of the slice token
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        // if the asset is local execute the transfer right away
        for (uint256 i = 0; i < positions.length; i++) {
            uint256 _amount = CrossChainData.calculateAmountOutMin(txInfo.quantity, positions[i].units);

            if (isPositionLocal(positions[i])) {
                bool success = IERC20(positions[i].token).transfer(txInfo.user, _amount);
                require(success, "SliceCore: Underlying asset transfer failed");
                // increase ready signal after each local transfer
                transactionCompleteSignals[_redeemID].signals++;
            } else {
                // if asset is not local send lz msg to Core contract on dst chain
                Chain memory dstChain = chainInfo.getChainInfo(positions[i].chainId);

                CrossChainSignal memory ccs = CrossChainSignal(
                    _redeemID,
                    uint32(block.chainid),
                    TransactionType.REDEEM,
                    false,
                    txInfo.user,
                    positions[i].token,
                    _amount
                );
                bytes memory ccsEncoded = abi.encode(ccs);

                bytes memory _lzSendOpts = CrossChainData.createLzSendOpts(200000, 500000000000000);

                endpoint.send{value: msg.value}(
                    MessagingParams(
                        dstChain.lzEndpointId, _getPeerOrRevert(dstChain.lzEndpointId), ccsEncoded, _lzSendOpts, false
                    ),
                    payable(address(this))
                );
            }
        }

        // if all signals are in call redeemComplete on token contract
        if (checkPendingTransactionCompleteSignals(_redeemID)) {
            emit UnderlyingAssetsRedeemed(msg.sender, txInfo.quantity, txInfo.user);
            SliceToken(msg.sender).redeemComplete(_redeemID);
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

    /**
     * @dev See IPayloadExecutor - onPayloadReceive
     */
    function onPayloadReceive(bytes memory _data) external payable {
        // implement on payload receive, verify the transfer details on dst chain
        require(msg.sender == stargateAdapter, "SliceCore: Only Stargate adapter can call");
        SlicePayloadData memory payloadData = abi.decode(_data, (SlicePayloadData));
        uint256 balance = IERC20(payloadData.tokenOut).balanceOf(address(this));
        require(balance >= payloadData.amountOutMin, "SliceCore: Incorrect amount of token out");
        // implement layer zero msg send to main chain contract
        // get src lz chain id from payload data
        Chain memory srcChain = chainInfo.getChainInfo(payloadData.srcChainId);
        // create cross chain signal
        CrossChainSignal memory ccs = CrossChainSignal(
            payloadData.mintID, uint32(block.chainid), TransactionType.MINT, true, address(0), address(0), 0
        );
        // encode to bytes
        bytes memory ccsEncoded = abi.encode(ccs);

        bytes memory _lzSendOpts = CrossChainData.createLzSendOpts(200000, 500000000000000); // TODO: Calculate values programatically

        MessagingFee memory _fee = _quote(srcChain.lzEndpointId, ccsEncoded, _lzSendOpts, false);

        console.log(_fee.nativeFee);

        // call send on layer zero endpoint
        endpoint.send{value: _fee.nativeFee}(
            MessagingParams(
                srcChain.lzEndpointId, _getPeerOrRevert(srcChain.lzEndpointId), ccsEncoded, _lzSendOpts, false
            ),
            payable(address(this))
        );
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32, /* _guid */ // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address, /* _executor */ // the Executor address.
        bytes calldata /* _extraData */ // arbitrary data appended by the Executor
    ) internal override {
        // verify that it was sent by the correct layer zero endpoint
        require(msg.sender == address(endpoint), "SliceCore: lzReceive not called by endpoint");

        // verify that the msg came from the slice core address
        require(
            address(uint160(uint256(_origin.sender))) == address(this),
            "SliceCore: lzSend not initiated by cross-chain SliceCore"
        );

        CrossChainSignal memory ccs = abi.decode(payload, (CrossChainSignal));

        if (ccs.txType == TransactionType.MINT) {
            handleSwapCompleteSignal(ccs);
        } else if (ccs.txType == TransactionType.REDEEM) {
            handleRedeemSignal(ccs);
        } else if (ccs.txType == TransactionType.REDEEM_COMPLETE) {
            handleRedeemCompleteSignal(ccs);
        }
    }

    function handleSwapCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];
        // verify that the mint id from the payload exists
        require(isSliceTokenRegistered(txCompleteSignals.token), "SliceCore: Unknown mint ID");

        // verify that the payload status is OK
        require(ccs.success, "SliceCore: Cross-chain swap failed");

        // then register complete signal
        transactionCompleteSignals[ccs.id].signals++;

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsPurchased(
                txCompleteSignals.token, txCompleteSignals.sliceTokenQuantity, txCompleteSignals.user
            );
            // if all complete signals received: call mintComplete on token
            SliceToken(txCompleteSignals.token).mintComplete(ccs.id);
        }
    }

    function handleRedeemSignal(CrossChainSignal memory ccs) internal {
        bool success = IERC20(ccs.underlying).transfer(ccs.user, ccs.units);
        require(success, "SliceCore: Cross-chain redeem failed");

        // send cross chain success msg
        CrossChainSignal memory _ccsResponse = CrossChainSignal(
            ccs.id, uint32(block.chainid), TransactionType.REDEEM_COMPLETE, true, address(0), address(0), 0
        );

        bytes memory _ccsResponseEncoded = abi.encode(_ccsResponse);

        bytes memory _lzSendOpts = CrossChainData.createLzSendOpts(200000, 500000000000000);

        Chain memory srcChain = chainInfo.getChainInfo(ccs.srcChainId);

        MessagingFee memory _fee = _quote(srcChain.lzEndpointId, _ccsResponseEncoded, _lzSendOpts, false);

        console.log("Fee: ");
        console.log(_fee.nativeFee);

        endpoint.send{value: _fee.nativeFee}(
            MessagingParams(
                srcChain.lzEndpointId, _getPeerOrRevert(srcChain.lzEndpointId), _ccsResponseEncoded, _lzSendOpts, false
            ),
            payable(address(this))
        );
    }

    function handleRedeemCompleteSignal(CrossChainSignal memory ccs) internal {
        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.id];

        require(isSliceTokenRegistered(txCompleteSignals.token), "SliceCore: Unknown redeem ID");

        require(ccs.success, "SliceCore: Cross-chain redeem failed");

        transactionCompleteSignals[ccs.id].signals++;

        if (checkPendingTransactionCompleteSignals(ccs.id)) {
            emit UnderlyingAssetsRedeemed(
                txCompleteSignals.token, txCompleteSignals.sliceTokenQuantity, txCompleteSignals.user
            );

            SliceToken(txCompleteSignals.token).redeemComplete(ccs.id);
        }
    }

    function isPositionLocal(Position memory _position) internal view returns (bool) {
        return _position.chainId == block.chainid;
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

        // TODO: Estimate gas correctly for swap
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

    function createAdapterData(Chain memory _dstChain, uint256 _maxEstimatedPrice, uint256 gasForSwap)
        private
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

    function setCrossChainGas(CrossChainGas memory _crossChainGas) external onlyOwner {
        crossChainGas = _crossChainGas;
    }

    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external {}

    receive() external payable {}
}
