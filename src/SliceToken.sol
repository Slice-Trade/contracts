// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/ISliceToken.sol";
import "./interfaces/ISliceCore.sol";
import "./utils/Utils.sol";

contract SliceToken is ISliceToken, ERC20 {
    IERC20 public paymentToken;

    address public sliceCore;
    Position[] public positions;

    mapping(bytes32 => SliceTransactionInfo) public mints;
    mapping(bytes32 => SliceTransactionInfo) public rebalances;
    mapping(bytes32 => SliceTransactionInfo) public redeems;

    modifier onlySliceCore() {
        require(msg.sender == sliceCore, "SliceToken: Only Slice Core can call");
        _;
    }

    constructor(string memory _name, string memory _symbol, Position[] memory _positions, address _paymentToken, address _sliceCore)
        ERC20(_name, _symbol)
    {
        paymentToken = IERC20(_paymentToken);

        sliceCore = _sliceCore;

        for (uint256 i = 0; i < _positions.length; i++) {
            positions.push(_positions[i]);
        }
    }

    /**
     * @dev See ISliceToken - mint
     */
    function mint(uint256 _sliceTokenQuantity, uint256[] memory _maxEstimatedPrices, bytes[] memory _routes) external returns (bytes32) {
        require(_sliceTokenQuantity > 0, "SliceToken: Slice token quantity can't be zero");

        require(_maxEstimatedPrices.length == _routes.length && _maxEstimatedPrices.length == positions.length, "SliceToken: Incorrect length for prices or routes");

        uint256 sumPrice = Utils.sumMaxEstimatedPrices(_maxEstimatedPrices);

        paymentToken.transferFrom(msg.sender, address(sliceCore), sumPrice);
        
        bytes32 mintId = keccak256(abi.encodePacked(msg.sender, address(this), _sliceTokenQuantity, sumPrice, block.timestamp));

        SliceTransactionInfo memory txInfo = SliceTransactionInfo(
            mintId,
            _sliceTokenQuantity,
            msg.sender,
            bytes("")
        );

        mints[mintId] = txInfo;

        ISliceCore(sliceCore).purchaseUnderlyingAssets(mintId, _sliceTokenQuantity, _maxEstimatedPrices, _routes);

        return mintId;
    }

    /**
     * @dev See ISliceToken - mintComplete
     */
    function mintComplete(bytes32 _mintID) external {
        // TODO
    }

    /**
     * @dev See ISliceToken - rebalance
     */
    function rebalance(Position[] calldata _positions) external returns (bytes32) {
        // TODO
    }

    /**
     * @dev See ISliceToken - rebalanceComplete
     */
    function rebalanceComplete(bytes32 _rebalanceID) external {
        // TODO
    }

    /**
     * @dev See ISliceToken - redeem
     */
    function redeem(uint256 _sliceTokenQuantity) external returns (bytes32) {
        // TODO
    }

    /**
     * @dev See ISliceToken - redeemComplete
     */
    function redeemComplete(bytes32 _redeemID) external {
        // TODO
    }

    /**
     * @dev See ISliceToken - getPositions
     */
    function getPositions() external view returns (Position[] memory) {
        return positions;
    }

    function getNumberOfPositions() external view returns (uint256) {
        return positions.length;
    }

    function getMint(bytes32 _id) external view returns (SliceTransactionInfo memory) {
        return mints[_id];
    }

    function getRedeem(bytes32 _id) external view returns (SliceTransactionInfo memory) {
        return redeems[_id];
    }

    function getRebalance(bytes32 _id) external view returns (SliceTransactionInfo memory) {
        return rebalances[_id];
    }
}
