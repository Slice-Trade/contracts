// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../external/IPayloadExecutor.sol";
import "../external/lz/ILayerZeroReceiver.sol";
import "../Structs.sol";
import "./ISliceToken.sol";

interface ISliceCore is IPayloadExecutor, ILayerZeroReceiver {
    /* Emitted when a new slice token is created */
    event SliceTokenCreated(address indexed token);
    /* Emitted when the underlying assets of a Slice token are purchased during a Slice token mint */
    event UnderlyingAssetsPurchased(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);
    /* Emitted when the Slice token creator successfully rebalances a Slice token's positions */
    event UnderlyingAssetsRebalanced(address indexed token);
    /* Emitted when the underlying assets in a Slice token are redeemed by a Slice token owner */
    event UnderlyingAssetsRedeemed(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);

    /**
     * @dev Deploys a new Slice token contract. Can only be called by verified addresses.
     * @param _positions The Slice token's underlying positions 
     */
    function createSlice(Position[] calldata _positions) external;

    /**
     * @dev Returns whether a given address is authorized to create a Slice token.
     * @param _user The address of the user
     */
    function canCreateSlice(address _user) external view returns (bool);

    /**
     * @dev Purchases the underlying assets for a given slice token (msg.sender).
     * @param _mintID The ID that uniquely identifies this mint transaction within the sysem
     * @param _sliceTokenQuantity The quantity of slice tokens to purchase the underlying assets for
     * @param _maxEstimatedPrice The maximum estimated price of all the underlying assets combined. In USDC (6 decimals)
     */
    function purchaseUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external;

    /**
     * @dev Sells/buy the Slice token (msg.sender) underlying assets to rebalance to the new positions
     * @param _rebalanceID The ID that uniquely identifies this transaction within the system
     * @param _positions The new positions to rebalance to
     */
    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external;

    /**
     * @dev Transfers out the underlying assets for a given Slice token to the given user.
     * @param _redeemID The ID that uniquely identifies this transaction within the system
     * @param _redeemInfo The details of the underlying asset redeeming.
     */
    function redeemUnderlying(bytes32 _redeemID, RedeemInfo memory _redeemInfo) external;

    /**
     * @dev Enables/disables the creation of new Slice tokens. Can only be called by contract owner.
     * @param _isEnabled If true token creation is enabled, otherwise disabled
     */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external;

    /**
     * @dev Returns the number of Slice tokens registered (created) in the contract.
     */
    function getRegisteredSliceTokensCount() external view returns (uint256);

    /**
     * @dev Returns whether a given address is a registered slice token or not.
     * @param _token The address to check
     */
    function isSliceTokenRegistered(address _token) external view returns (bool);

}