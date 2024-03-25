// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISliceCore.sol";
import "./SliceToken.sol";

contract SliceCore is ISliceCore, Ownable {
    address public paymentToken;

    mapping(address => bool) public approvedSliceTokenCreators;

    bool public isTokenCreationEnabled;

    mapping(address => bool) public registeredSliceTokens;
    uint256 public registeredSliceTokensCount;

    mapping(bytes32 => ReadySignal) private readySignals;

    constructor(address _paymentToken) Ownable(msg.sender) {
        paymentToken = _paymentToken;
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
    function purchaseUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external {
        // check that slice token (msg.sender) is registered
        require(registeredSliceTokens[msg.sender], "SliceCore: Only registered Slice token can call");

        require(IERC20(paymentToken).balanceOf(address(this)) >= _maxEstimatedPrice, "SliceCore: Max estimated price not transferred to contract");

        SliceTransactionInfo memory txInfo = ISliceToken(msg.sender).getMint(_mintID);
        require(txInfo.id == _mintID, "SliceCore: Mint ID does not exist");

        readySignals[_mintID].token = msg.sender;

        // get the underlying positions from the slice token
        Position[] memory positions = SliceToken(msg.sender).getPositions();

        for (uint256 i = 0; i < positions.length; i++) {
            // if asset is local execute swap right away: (check block.chainid)
            if (isPositionLocal(positions[i])) {
                bool success = executeLocalSwap();
                // increase the ready signal after each local swap
                if (success) {
                    readySignals[_mintID].signals++;
                }
            } else {
                executeCrossChainSwap();
            }
        }

        // checks the signal count after each swap, in each callback
        // if all signals are in -> call mintComplete on token contract
        if (checkPendingTransactionCompleteSignals(_mintID)) {
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
    function isSliceTokenRegistered(address _token) external view returns (bool) {
        return registeredSliceTokens[_token];
    }

    /**
     * @dev See ISliceCore - getRegisteredSliceTokensCount
     */
    function getRegisteredSliceTokensCount() external view returns (uint256) {
        return registeredSliceTokensCount;
    }

    /**
     * @dev See IPayloadExecutor - onPayloadReceive
     */
    function onPayloadReceive(bytes memory _data) external payable {
        // TODO
    }

    /**
     * @dev See ILayerZeroReceiver - lzReceive
     */
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        // TODO
    }

    function isPositionLocal(Position memory _position) internal view returns (bool) {
        return _position.chainId == block.chainid;
    }

    function executeLocalSwap() internal returns (bool) {

    }

    function executeCrossChainSwap() internal {
        // TODO
        // if asset is not local:

        // execute sushi X swap bridge with swap data and payload data

        // implement on payload receive, verify the transfer details

        // implement layer zero msg send to main chain contract

        // in main chain contract implement lzReceive to handle cross chain msg --> verify msg and increment ok signals

        // if all signals in -> call mint complete on token contract
    }

    function checkPendingTransactionCompleteSignals(bytes32 _id) internal view returns (bool) {
        ReadySignal memory _readySignal = readySignals[_id];
        uint256 _numOfPositions = ISliceToken(_readySignal.token).getNumberOfPositions();
        return _readySignal.signals == _numOfPositions;
    }

    function allowInitializePath(Origin calldata _origin) external view returns (bool) {
        // TODO
    }

    function nextNonce(uint32 _eid, bytes32 _sender) external view returns (uint64) {
        // TODO
    }
}
