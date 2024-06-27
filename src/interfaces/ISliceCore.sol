// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@lz-oapp-v2/interfaces/ILayerZeroReceiver.sol";
import "../Structs.sol";
import "./ISliceCoreErrors.sol";

interface ISliceCore is ILayerZeroReceiver, ISliceCoreErrors {
    /* Emitted when a new slice token is created */
    event SliceTokenCreated(address indexed token);
    /* Emitted when the underlying assets of a Slice token are purchased or transferred during a Slice token mint or manual mint */
    event UnderlyingAssetsCollected(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);
    /* Emitted when the underlying assets in a Slice token are redeemed by a Slice token owner */
    event UnderlyingAssetsRedeemed(address indexed token, uint256 indexed sliceTokenQuantity, address indexed owner);
    /* Emitted when the underlying assets that were transferred during a failed mint are refunded to the user */
    event UnderlyingAssetsRefunded(address indexed token, bytes32 indexed mintId, address indexed owner);
    /* Emitted when the Slice token creation is enabled/disabled */
    event ChangedSliceTokenCreationEnabled(bool indexed isEnabled);
    /* Emitted when an address is added/rmemoved from the list of allowed Slice token creators */
    event ChangedApprovedSliceTokenCreator(address indexed user, bool indexed isApproved);
    /* Emitted when the base gas used to calculate the full gas sent cross chain in LayerZero calls is modified for a given cross chain message type */
    event SetLzBaseGas(CrossChainSignalType indexed ccsType, uint128 indexed gas);

    /**
     * @dev Deploys a new Slice token contract. Can only be called by verified addresses.
     *
     * @param positions The Slice token's underlying positions
     *
     * @return address The address of the new slice token
     */
    function createSlice(string calldata name, string calldata symbol, Position[] calldata positions)
        external
        returns (address);

    /**
     * @dev Transfers the underlying assets from the user to the contract
     *
     * @param mintID The ID that uniquely identifies this mint transaction within the system
     */
    function collectUnderlying(bytes32 mintID, uint128[] calldata fees) external payable;

    /**
     * @dev Transfers out the underlying assets for a given Slice token to the given user.
     *
     * @param redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemUnderlying(bytes32 redeemID, uint128[] calldata fees) external payable;

    /**
     * @dev Handles the refund procedure for a failed mint
     *
     * @param txInfo The transaction info struct for the failed mint
     */
    function refund(SliceTransactionInfo memory txInfo, uint128[] calldata fees) external payable;

    /**
     * @dev Returns whether a given address is authorized to create a Slice token.
     *
     * @param user The address of the user
     *
     * @return bool Whether the address can create slice tokens
     */
    function canCreateSlice(address user) external view returns (bool);

    /**
     * @dev Enables/disables the creation of new Slice tokens. Can only be called by contract owner.
     *
     * @param _isEnabled If true token creation is enabled, otherwise disabled
     */
    function changeSliceTokenCreationEnabled(bool _isEnabled) external;

    /**
     * @dev Adds or removes an address from the list of addresses that can create new Slice tokens
     *
     * @param user The address to approve/remove
     * @param isApproved Whether to approve/disapprove
     */
    function changeApprovedSliceTokenCreator(address user, bool isApproved) external;

    /**
     * @dev Sets the base gas used to calculate the full gas sent cross chain in LayerZero calls for a cross chain message type
     *
     * @param ccsType The cross-chain message type
     * @param gas The amount of base gas
     */
    function setLzBaseGas(CrossChainSignalType ccsType, uint128 gas) external;

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
     * @param idx The index in the registeredSliceTokens array.
     *
     * @return address The address of the slice token at the given index
     */
    function getRegisteredSliceToken(uint256 idx) external view returns (address);

    /**
     * @dev Returns whether a given address is a registered slice token or not.
     *
     * @param token The address to check
     *
     * @return bool Whether the address is a registered slice token
     */
    function isSliceTokenRegistered(address token) external view returns (bool);
}
