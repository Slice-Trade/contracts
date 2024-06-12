// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Structs.sol";

interface ISliceToken is IERC20 {
    /* Emitted when a new Slice token is minted */
    event SliceMinted(address indexed to, uint256 indexed quantity);
    /* Emitted when a Slice token is exchanged for the underlying assets by the owner */
    event SliceRedeemed(address indexed to, uint256 indexed quantity);
    /* Emitted when a Slice token manual mint has failed */
    event SliceMintFailed(address indexed to, uint256 indexed quantity);
    /* Emitted when a Slice token manual mint that failed has been refunded */
    event RefundCompleted(address indexed to, uint256 indexed quantity);

    error UnorderedChainIds();
    error NotSliceCore();
    error AmountLocked();
    error ZeroTokenQuantity();
    error InsufficientTokenQuantity();
    error IncorrectPricesOrRoutesLength();
    error MintIdDoesNotExist();
    error RedeemIdDoesNotExist();
    error InvalidTransactionState();
    error InsufficientBalance();
    error AlreadySet();
    error MintFailed();

    /**
     * @dev Called by the SliceCore contract when a mint transaction is confirmed completed by all the cross-chain contracts
     *
     * @param mintID The ID that uniquely identifies this transaction within the system
     */
    function mintComplete(bytes32 mintID) external;

    /**
     * @dev Redeems the underlying assets in a Slice token and burns the Slice token.
     *
     * @param sliceTokenQuantity The quantity of slice tokens to redeem
     *
     * @return bytes32 The redeem ID
     */
    function redeem(uint256 sliceTokenQuantity) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a redeem transaction is confirmed completed by all the cross-chain contracts
     *
     * @param redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemComplete(bytes32 redeemID) external;

    /**
     * @dev Mints a new Slice token using the manual mint flow - assuming the underlying assets are in the user wallet and approved to spend
     *
     * @param sliceTokenQuantity The quantity of slice tokens to mint
     *
     * @return bytes32 The mint ID
     */
    function mint(uint256 sliceTokenQuantity) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a manual mint transaction has failed
     * @param mintID The ID that uniquely identifies this transaction within the system
     */
    function mintFailed(bytes32 mintID) external;

    function refund(bytes32 mintID) external payable;

    function refundComplete(bytes32 mintID) external;

    /**
     * @dev Returns the Slice token's underlying positions
     *
     * @return Position[] The tokens's underlying positions
     */
    function getPositions() external view returns (Position[] memory);

    /**
     * @dev Returns the number of positions in the token
     *
     * @return uint256 The number of positions
     */
    function getNumberOfPositions() external view returns (uint256);

    /**
     * @dev Returns the Mint transaction info for the given ID
     *
     * @param id The mint ID
     *
     * @return SliceTransactionInfo Struct holding the information about the mint
     */
    function getMint(bytes32 id) external view returns (SliceTransactionInfo memory);

    /**
     * @dev Returns the Redeem transaction info for the given ID
     *
     * @param id The redeem ID
     *
     * @return SliceTransactionInfo Struct holding the information about the mint
     */
    function getRedeem(bytes32 id) external view returns (SliceTransactionInfo memory);

    function getPosIdx(address token) external view returns (uint256);

    function getPosAtIdx(uint256 idx) external view returns (Position memory);
}
