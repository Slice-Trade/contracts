// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Structs.sol";

interface ISliceToken is IERC20 {
    /* Emitted when a new Slice token is minted */
    event SliceMinted(address indexed to, uint256 indexed quantity);
    /* Emitted when a Slice token is rebalanced by its creator */
    event SliceRebalanced(address indexed token);
    /* Emitted when a Slice token is exchanged for the underlying assets by the owner */
    event SliceRedeemed(address indexed to, uint256 indexed quantity);

    /**
     * @dev Mints a new Slice token
     * @param _sliceTokenQuantity The quantity of slice tokens to purchase
     * @param _maxEstimatedPrice The maximum estimated price of all the underlying assets combined. In USDC (6 decimals)
     */
    function mint(uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external;

    /**
     * @dev Called by the SliceCore contract when a mint transaction is confirmed completed by all the cross-chain contracts
     * @param _mintID The ID that uniquely identifies this transaction within the system
     */
    function mintComplete(bytes32 _mintID) external;

    /**
     * @dev Rebalances the underlying positions in the Slice token. Can only be called by contract owner.
     * @param _positions The new positions to rebalance to 
     */
    function rebalance(Position[] calldata _positions) external;

    /**
     * @dev Called by the SliceCore contract when a rebalance transaction is confirmed completed by all the cross-chain contracts
     * @param _rebalanceID The ID that uniquely identifies this transaction within the system
     */
    function rebalanceComplete(bytes32 _rebalanceID) external;

    /**
     * @dev Redeems the underlying assets in a Slice token and burns the Slice token.
     * @param _sliceTokenQuantity The quantity of slice tokens to redeem
     */
    function redeem(uint256 _sliceTokenQuantity) external;

    /**
     * @dev Called by the SliceCore contract when a redeem transaction is confirmed completed by all the cross-chain contracts
     * @param _redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemComplete(bytes32 _redeemID) external;

    /**
     * @dev Returns the Slice token's underlying positions
     */
    function getPositions() external view returns (Position[] memory);

    /**
     * @dev Returns the mint ID for the given index in the mintIds array
     * @param _idx The index in the mintIds array
     */
    function getMintId(uint256 _idx) external view returns (bytes32);

    /**
     * @dev Returns the rebalance ID for the given index in the rebalanceIds array
     * @param _idx The index in the rebalanceIds array
     */
    function getRebalanceId(uint256 _idx) external view returns (bytes32);

    /**
     * @dev Returns the redeem ID for the given index in the redeemIds array
     * @param _idx The index in the redeemIds array
     */
    function getRedeemId(uint256 _idx) external view returns (bytes32);
}