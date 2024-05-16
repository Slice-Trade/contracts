// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../external/IPayloadExecutor.sol";
import "@lz-oapp-v2/interfaces/ILayerZeroReceiver.sol";
import "../Structs.sol";
import "./ISliceCoreErrors.sol";

interface ISliceCore is IPayloadExecutor, ILayerZeroReceiver, ISliceCoreErrors {
    /* Emitted when a new slice token is created */
    event SliceTokenCreated(address indexed token);
    /* Emitted when the underlying assets of a Slice token are purchased or transferred during a Slice token mint or manual mint */
    event UnderlyingAssetsProcured(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);
    /* Emitted when the underlying assets in a Slice token are redeemed by a Slice token owner */
    event UnderlyingAssetsRedeemed(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);

    /**
     * @dev Deploys a new Slice token contract. Can only be called by verified addresses.
     *
     * @param _positions The Slice token's underlying positions
     *
     * @return address The address of the new slice token
     */
    function createSlice(string calldata _name, string calldata _symbol, Position[] calldata _positions)
        external
        returns (address);

    /**
     * @dev Returns whether a given address is authorized to create a Slice token.
     *
     * @param _user The address of the user
     *
     * @return bool Whether the address can create slice tokens
     */
    function canCreateSlice(address _user) external view returns (bool);

    /**
     * @dev Purchases the underlying assets for a given slice token (msg.sender).
     *
     * @param _mintID The ID that uniquely identifies this mint transaction within the sysem
     * @param _sliceTokenQuantity The quantity of slice tokens to purchase the underlying assets for
     * @param _maxEstimatedPrices The maximum estimated price for each underlying asset. In USDC (6 decimals)
     */
    function purchaseUnderlyingAssets(
        bytes32 _mintID,
        uint256 _sliceTokenQuantity,
        uint256[] memory _maxEstimatedPrices,
        bytes[] memory _routes
    ) external payable;

    /**
     * @dev Transfers the underlying assets from the user to the contract
     *
     * @param _mintID The ID that uniquely identifies this mint transaction within the system
     * @param _sliceTokenQuantity The quantity of slice tokens to mint to the user
     */
    function collectUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity) external payable;

    /**
     * @dev Transfers out the underlying assets for a given Slice token to the given user.
     *
     * @param _redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemUnderlying(bytes32 _redeemID) external payable;

    function refund(SliceTransactionInfo memory _txInfo) external payable;

    /**
     * @dev Enables/disables the creation of new Slice tokens. Can only be called by contract owner.
     *
     * @param _isEnabled If true token creation is enabled, otherwise disabled
     */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external;

    /**
     * @dev Adds or removes an address from the list of addresses that can create new Slice tokens
     *
     * @param _user The address to approve/remove
     * @param _isApproved Whether to approve/disapprove
     */
    function changeApprovedSliceTokenCreator(address _user, bool _isApproved) external;

    /**
     * @dev Returns the number of Slice tokens registered (created) in the contract.
     *
     * @return uint256 The number of registered slice tokens
     */
    function getRegisteredSliceTokensCount() external view returns (uint256);

    /**
     * @dev Returns all the registered Slice tokens.
     *
     * @return address[] All the registered slice tokens
     */
    function getRegisteredSliceTokens() external view returns (address[] memory);

    /**
     * @dev Returns a registered Slice token at the given index.
     *
     * @param _idx The index in the registeredSliceTokens array.
     *
     * @return address The address of the slice token at the given index
     */
    function getRegisteredSliceToken(uint256 _idx) external view returns (address);

    /**
     * @dev Returns whether a given address is a registered slice token or not.
     *
     * @param _token The address to check
     *
     * @return bool Whether the address is a registered slice token
     */
    function isSliceTokenRegistered(address _token) external view returns (bool);
}
