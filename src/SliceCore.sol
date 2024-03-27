// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import "./external/ISushiXSwapV2.sol";
import "./external/IRouteProcessor.sol";
import "./external/IStargateAdapter.sol";
import "./external/ISushiXSwapV2Adapter.sol";
import "./interfaces/ISliceCore.sol";
import "./utils/Route.sol";
import "./utils/Utils.sol";
import "./utils/ChainInfo.sol";
import "./SliceToken.sol";

contract SliceCore is ISliceCore, Ownable, OApp {
    address public immutable lzEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    address public paymentToken;

    ISushiXSwapV2 public sushiXSwap;

    address public stargateAdapter;

    address public axelarAdapter;

    ChainInfo public chainInfo;

    mapping(address => bool) public approvedSliceTokenCreators;

    bool public isTokenCreationEnabled;

    mapping(address => bool) public registeredSliceTokens;
    address[] public registeredSliceTokensArray;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 => TransactionCompleteSignals) private transactionCompleteSignals;

    constructor(address _paymentToken, address _sushiXSwap, address _stargateAdapter, address _axelarAdapter)
        Ownable(msg.sender)
        OApp(lzEndpoint, msg.sender)
    {
        paymentToken = _paymentToken;
        sushiXSwap = ISushiXSwapV2(_sushiXSwap);
        chainInfo = new ChainInfo();
        stargateAdapter = _stargateAdapter;
        axelarAdapter = _axelarAdapter;
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

        SliceToken token = new SliceToken(_name, _symbol, _positions, paymentToken, address(this));
        registeredSliceTokens[address(token)] = true;
        registeredSliceTokensCount++;

        emit SliceTokenCreated(address(token));

        return address(token);
    }

    /**
     * @dev See ISliceCore - purchaseUnderlyingAssets
     */
    function purchaseUnderlyingAssets(
        bytes32 _mintID,
        uint256 _sliceTokenQuantity,
        uint256[] memory _maxEstimatedPrices,
        bytes[] memory _routes
    ) external {
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
                bool success =
                    executeLocalSwap(msg.sender, _sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], _routes[i]);
                // increase the ready signal after each local swap
                if (success) {
                    transactionCompleteSignals[_mintID].signals++;
                }
            } else {
                executeCrossChainSwap(
                    _mintID, msg.sender, _sliceTokenQuantity, _maxEstimatedPrices[i], positions[i], txInfo, _routes[i]
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
     * @dev See ISliceCore - rebalanceUnderlying
     */
    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external {
        // TODO
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 _redeemID, SliceTransactionInfo memory _txInfo) external {
        // TODO
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

    /**
     * @dev See IPayloadExecutor - onPayloadReceive
     */
    function onPayloadReceive(bytes memory _data) external payable {
        // TODO
        // implement on payload receive, verify the transfer details on dst chain
        require(msg.sender == stargateAdapter, "SliceCore: Only Stargate adapter can call");
        SlicePayloadData memory payloadData = abi.decode(_data, (SlicePayloadData));
        uint256 balance = IERC20(payloadData.tokenOut).balanceOf(address(this));
        require(balance >= payloadData.amountOutMin, "SliceCore: Incorrect amount of token out");
        // implement layer zero msg send to main chain contract
        // get src lz chain id from payload data
        Chain memory srcChain = chainInfo.getChainInfo(payloadData.srcChainId);
        // create cross chain signal
        CrossChainSignal memory ccs = CrossChainSignal(payloadData.mintID, true);
        // encode to bytes
        bytes memory ccsEncoded = abi.encode(ccs);
        // call _lzSend
        _lzSend(
            srcChain.lzEndpointId,
            ccsEncoded,
            "", // TODO: Enforce security options
            MessagingFee(msg.value, 0),
            payable(address(this))
        );
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32 /* _guid */, // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address /* _executor */, // the Executor address.
        bytes calldata /* _extraData */ // arbitrary data appended by the Executor
    ) internal override {
        // in main chain contract implement lzReceive to handle cross chain msg --> verify msg and increment ok signals
        // if all signals in -> call mint complete on token contract
        
        // verify that it was sent by the correct layer zero endpoint
        require(msg.sender == lzEndpoint, "SliceCore: lzReceive not called by endpoint");

        // verify that the msg came from the slice core address
        require(address(uint160(uint256(_origin.sender))) == address(this), "SliceCore: lzSend not initiated by cross-chain SliceCore");

        CrossChainSignal memory ccs = abi.decode(payload, (CrossChainSignal));

        TransactionCompleteSignals memory txCompleteSignals = transactionCompleteSignals[ccs.mintID];
        // verify that the mint id from the payload exists
        require(isSliceTokenRegistered(txCompleteSignals.token), "SliceCore: Unknown mint ID");

        // verify that the payload status is OK
        require(ccs.success, "SliceCore: Cross-chain swap failed");

        // then register complete signal
        transactionCompleteSignals[ccs.mintID].signals++;

        if (checkPendingTransactionCompleteSignals(ccs.mintID)) {
            emit UnderlyingAssetsPurchased(msg.sender, txCompleteSignals.sliceTokenQuantity, txCompleteSignals.user);
            // if all complete signals received: call mintComplete on token
            SliceToken(msg.sender).mintComplete(ccs.mintID);
        }
    }

    function isPositionLocal(Position memory _position) internal view returns (bool) {
        return _position.chainId == block.chainid;
    }

    function executeLocalSwap(
        address _sliceToken,
        uint256 _sliceTokenQuantity,
        uint256 _maxEstimatedPrice,
        Position memory _position,
        bytes memory _route
    ) internal returns (bool) {
        IERC20(paymentToken).approve(address(sushiXSwap), _maxEstimatedPrice);

        uint256 amountIn = _maxEstimatedPrice;
        uint256 amountOutMin = _position.units * _sliceTokenQuantity; // TODO

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: paymentToken,
            amountIn: amountIn,
            tokenOut: _position.token,
            amountOutMin: amountOutMin,
            to: _sliceToken,
            route: _route
        });

        bytes memory rpd_encoded = abi.encode(rpd);

        sushiXSwap.swap(rpd_encoded);

        uint256 balanceAfterSwap = IERC20(_position.token).balanceOf(_sliceToken);
        return balanceAfterSwap >= _position.units;
    }

    // TODO: get fees from both axelar and stargate, compare them and go with the lowest fee bridge
    function executeCrossChainSwap(
        bytes32 _mintId,
        address _sliceToken,
        uint256 _sliceTokenQuantity,
        uint256 _maxEstimatedPrice,
        Position memory _position,
        SliceTransactionInfo memory _txInfo,
        bytes memory _route
    ) internal {
        IERC20(paymentToken).approve(address(sushiXSwap), _maxEstimatedPrice);

        uint256 amountOutMin = _position.units * _sliceTokenQuantity; // TODO

        bytes memory rpd_encoded_dst =
            createRouteProcessorDataEncoded(paymentToken, _position.token, amountOutMin, _sliceToken, _route);

        bytes memory payloadDataEncoded = createPayloadDataEncoded(_mintId, _position.token, amountOutMin, _txInfo.data);

        Chain memory dstChain = chainInfo.getChainInfo(_position.chainId);

        uint256 gasNeeded = getGasNeeded(dstChain.stargateChainId, _sliceToken, rpd_encoded_dst, payloadDataEncoded);

        sushiXSwap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: stargateAdapter,
                tokenIn: paymentToken,
                amountIn: _maxEstimatedPrice,
                to: address(this), // TODO SliceCore deployed to all chains with same address!
                adapterData: createAdapterData(dstChain.stargateChainId, _maxEstimatedPrice, amountOutMin, 250000)
            }), // bridge params
            address(this), // refund address
            rpd_encoded_dst, // swap data
            payloadDataEncoded // payload data
        );
    }

    function createAdapterData(
        uint16 stargateChainId,
        uint256 _maxEstimatedPrice,
        uint256 amountOutMin,
        uint256 gasForSwap
    ) private view returns (bytes memory _adapterData) {
        _adapterData = abi.encode(
            stargateChainId, // dst chain id
            paymentToken, // token in
            1, // src pool id - USDC
            1, // dst pool id - USDC
            _maxEstimatedPrice, // amount,
            amountOutMin, // amountMin,
            0, // dust
            stargateAdapter, // receiver
            address(this), // to
            gasForSwap // gas
        );
    }

    function createRouteProcessorDataEncoded(
        address _paymentToken,
        address _token,
        uint256 amountOutMin,
        address _sliceToken,
        bytes memory _route
    ) private pure returns (bytes memory) {
        return abi.encode(
            IRouteProcessor.RouteProcessorData({
                tokenIn: _paymentToken,
                amountIn: 0, // amount in doesnt matter since we use amount bridged
                tokenOut: _token,
                amountOutMin: amountOutMin,
                to: _sliceToken,
                route: _route
            })
        );
    }

    function getGasNeeded(
        uint16 stargateChainId,
        address _sliceToken,
        bytes memory swapDataEncoded,
        bytes memory payloadDataEncoded
    ) private view returns (uint256) {
        (uint256 gasNeeded,) = IStargateAdapter(stargateAdapter).getFee(
            stargateChainId,
            1,
            stargateAdapter,
            250000,
            0,
            abi.encode(
                _sliceToken, // to
                swapDataEncoded, // swap data
                payloadDataEncoded // payload data
            )
        );

        return gasNeeded;
    }

    function createPayloadDataEncoded(bytes32 _mintId, address _token, uint256 amountOutMin, bytes memory _data)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            ISushiXSwapV2Adapter.PayloadData(
                address(this),
                100000, // TODO verify gas
                abi.encode(
                    SlicePayloadData(
                        block.chainid, // src chain id
                        _mintId, //mint ID
                        _token, // token Out
                        amountOutMin, // amount out min
                        _data // data
                    )
                ) // slice payload data
            )
        );
    }

    // checks the signal count after each swap, in each callback
    function checkPendingTransactionCompleteSignals(bytes32 _id) internal view returns (bool) {
        TransactionCompleteSignals memory _transactionCompleteSignal = transactionCompleteSignals[_id];
        uint256 _numOfPositions = ISliceToken(_transactionCompleteSignal.token).getNumberOfPositions();
        return _transactionCompleteSignal.signals == _numOfPositions;
    }
}
