// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISliceCore.sol";
import "./SliceToken.sol";

contract SliceCore is ISliceCore, Ownable {
    address public paymentToken;

    mapping(address => bool) public approvedSliceTokenCreators;

    bool public isTokenCreationEnabled;

    mapping(address => bool) public registeredSliceTokens;
    uint256 public registeredSliceTokensCount;

    constructor(address _paymentToken) Ownable(msg.sender) {
        paymentToken = _paymentToken;
    }
    
    /** @dev See ISliceCore - createSlice */
    function createSlice(string calldata _name, string calldata _symbol, Position[] calldata _positions) external returns (address) {
        require(canCreateSlice(msg.sender), "SliceCore: Unauthorized caller");
        require(isTokenCreationEnabled, "SliceCore: Slice token creation disabled");

        SliceToken token = new SliceToken(_name, _symbol, _positions, paymentToken, address(this));
        registeredSliceTokens[address(token)] = true;
        registeredSliceTokensCount++;

        emit SliceTokenCreated(address(token));

        return address(token);
    }

    /** @dev See ISliceCore - purchaseUnderlyingAssets */
    function purchaseUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external {
        // TODO
    }

    /** @dev See ISliceCore - rebalanceUnderlying */
    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external {
        // TODO
    }

    /** @dev See ISliceCore - redeemUnderlying */
    function redeemUnderlying(bytes32 _redeemID, SliceTransactionInfo memory _txInfo) external {
        // TODO
    }

    /** @dev See ISliceCore - changeSliceTokenCreationEnabled */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external onlyOwner {
        isTokenCreationEnabled = _isEnabled;
    }

    /** @dev See ISliceCore - changeApprovedSliceTokenCreator */
    function changeApprovedSliceTokenCreator(address _user, bool _isApproved) external onlyOwner {
        approvedSliceTokenCreators[_user] = _isApproved;
    }

    /** @dev See ISliceCore - canCreateSlice */
    function canCreateSlice(address _user) public view returns (bool) {
        return approvedSliceTokenCreators[_user];
    }

    /** @dev See ISliceCore - isSliceTokenRegistered */
    function isSliceTokenRegistered(address _token) external view returns (bool) {
        return registeredSliceTokens[_token];
    }

    /** @dev See ISliceCore - getRegisteredSliceTokensCount */
    function getRegisteredSliceTokensCount() external view returns (uint256) {
        return registeredSliceTokensCount;
    }

    /** @dev See IPayloadExecutor - onPayloadReceive */
    function onPayloadReceive(bytes memory _data) external payable {
        // TODO
    }

    /** @dev See ILayerZeroReceiver - lzReceive */
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        // TODO
    }

    function allowInitializePath(Origin calldata _origin) external view returns (bool) {
        // TODO
    }

    function nextNonce(uint32 _eid, bytes32 _sender) external view returns (uint64) {
        // TODO
    }
}