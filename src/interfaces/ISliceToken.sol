// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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

    error NotSliceCore();
    error AmountLocked();
    error ZeroTokenQuantity();
    error IncorrectPricesOrRoutesLength();
    error MintIdDoesNotExist();
    error RedeemIdDoesNotExist();
    error InvalidTransactionState();
    error InsufficientBalance();
    error AlreadySet();
    error MintFailed();

    /**
     * @dev Mints a new Slice token
     *
     * @param _sliceTokenQuantity The quantity of slice tokens to mint
     * @param _maxEstimatedPrices The maximum estimated price of all the underlying assets combined. In USDC (6 decimals)
     *
     * @return bytes32 The mint ID
     */
    function mint(uint256 _sliceTokenQuantity, uint256[] memory _maxEstimatedPrices, bytes[] memory _routes)
        external
        payable
        returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a mint transaction is confirmed completed by all the cross-chain contracts
     *
     * @param _mintID The ID that uniquely identifies this transaction within the system
     */
    function mintComplete(bytes32 _mintID) external;

    /**
     * @dev Redeems the underlying assets in a Slice token and burns the Slice token.
     *
     * @param _sliceTokenQuantity The quantity of slice tokens to redeem
     *
     * @return bytes32 The redeem ID
     */
    function redeem(uint256 _sliceTokenQuantity) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a redeem transaction is confirmed completed by all the cross-chain contracts
     *
     * @param _redeemID The ID that uniquely identifies this transaction within the system
     */
    function redeemComplete(bytes32 _redeemID) external;

    /**
     * @dev Mints a new Slice token using the manual mint flow - assuming the underlying assets are in the user wallet and approved to spend
     *
     * @param _sliceTokenQuantity The quantity of slice tokens to mint
     *
     * @return bytes32 The mint ID
     */
    function manualMint(uint256 _sliceTokenQuantity) external payable returns (bytes32);

    /**
     * @dev Called by the SliceCore contract when a manual mint transaction has failed
     * @param _mintID The ID that uniquely identifies this transaction within the system
     */
    function mintFailed(bytes32 _mintID) external;

    function refund(bytes32 _mintID) external payable;

    function refundComplete(bytes32 _mintID) external;

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
     * @param _id The mint ID
     *
     * @return SliceTransactionInfo Struct holding the information about the mint
     */
    function getMint(bytes32 _id) external view returns (SliceTransactionInfo memory);

    /**
     * @dev Returns the Redeem transaction info for the given ID
     *
     * @param _id The redeem ID
     *
     * @return SliceTransactionInfo Struct holding the information about the mint
     */
    function getRedeem(bytes32 _id) external view returns (SliceTransactionInfo memory);

    function getPosIdx(address _token) external view returns (uint256);

    function getPosAtIdx(uint256 _idx) external view returns (Position memory);
}
