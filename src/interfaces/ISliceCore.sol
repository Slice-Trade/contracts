// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../external/IPayloadExecutor.sol";
import "../external/lz/ILayerZeroReceiver.sol";
import "../Structs.sol";
import "./ISliceToken.sol";

interface ISliceCore is IPayloadExecutor, ILayerZeroReceiver {
    event SliceTokenCreated(address indexed token);

    event UnderlyingAssetsPurchased(address indexed token, uint256 indexed amount, address indexed owner);

    event UnderlyingAssetsRebalanced(address indexed token);

    event UnderlyingAssetsRedeemed(address indexed token, uint256 indexed amount, address indexed owner);

    function createSlice(Position[] calldata _positions) external;

    function canCreateSlice(address _user) external view returns (bool);

    function purchaseUnderlyingAssets(uint256 _sliceTokenAmount) external;

    function rebalanceUnderlying(Position[] calldata _positions) external;

    function redeemUnderlying(RedeemInfo memory _redeemInfo) external;
}