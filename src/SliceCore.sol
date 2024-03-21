// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/ISliceCore.sol";

contract SliceCore is ISliceCore {
    /** @dev See ISliceCore - createSlice */
    function createSlice(Position[] calldata _positions) external {
        // TODO
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
    function redeemUnderlying(bytes32 _redeemID, RedeemInfo memory _redeemInfo) external {
        // TODO
    }

    /** @dev See ISliceCore - changeSliceTokenCreationEnabled */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external {
        // TODO
    }

    /** @dev See ISliceCore - canCreateSlice */
    function canCreateSlice(address _user) external view returns (bool) {
        // TODO
    }

    /** @dev See ISliceCore - isSliceTokenRegistered */
    function isSliceTokenRegistered(address _token) external view returns (bool) {
        // TODO
    }

    /** @dev See ISliceCore - getRegisteredSliceTokensCount */
    function getRegisteredSliceTokensCount() external view returns (uint256) {
        // TODO
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