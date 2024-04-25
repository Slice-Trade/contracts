// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Structs.sol";

interface ISliceToken is IERC20 {
    /* Emitted when a new Slice token is minted */
    event SliceMinted(address indexed to, uint256 indexed quantity);
    /* Emitted when a Slice token is exchanged for the underlying assets by the owner */
    event SliceRedeemed(address indexed to, uint256 indexed quantity);

    /**
     * @dev Mints a new Slice token
     * @param _sliceTokenQuantity The quantity of slice tokens to purchase
     * @param _maxEstimatedPrices The maximum estimated price of all the underlying assets combined. In USDC (6 decimals)
     * @return bytes32 The mint ID
     */
    function mint(uint256 _sliceTokenQuantity, uint256[] memory _maxEstimatedPrices, bytes[] memory _routes) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a mint transaction is confirmed completed by all the cross-chain contracts
     * @param _mintID The ID that uniquely identifies this transaction within the system
     */
    function mintComplete(bytes32 _mintID) external;

    /**
     * @dev Redeems the underlying assets in a Slice token and burns the Slice token.
     * @param _sliceTokenQuantity The quantity of slice tokens to redeem
     * @return bytes32 The redeem ID 
     */
    function redeem(uint256 _sliceTokenQuantity) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a redeem transaction is confirmed completed by all the cross-chain contracts
     * @param _redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemComplete(bytes32 _redeemID) external;

    /**
     * @dev Returns the Slice token's underlying positions
     */
    function getPositions() external view returns (Position[] memory);

    function getNumberOfPositions() external view returns (uint256);

    function getMint(bytes32 _id) external view returns (SliceTransactionInfo memory);

    function getRedeem(bytes32 _id) external view returns (SliceTransactionInfo memory);
}
