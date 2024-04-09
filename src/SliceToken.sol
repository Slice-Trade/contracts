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

    string public category;
    string public description;

    mapping(bytes32 => SliceTransactionInfo) public mints;
    mapping(bytes32 => SliceTransactionInfo) public rebalances;
    mapping(bytes32 => SliceTransactionInfo) public redeems;

    mapping(address => uint256) public locked;

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

    function transfer(address to, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        require(verifyTransfer(msg.sender, amount), "SliceToken: Trying to transfer locked amount");
        bool success = super.transfer(to,amount);
        return success;
    }

    function setCategoryAndDescription(string calldata _category, string calldata _description) external {
        category = _category;
        description = _description;
    }

    /**
     * @dev See ISliceToken - mint
     */
    function mint(uint256 _sliceTokenQuantity, uint256[] memory _maxEstimatedPrices, bytes[] memory _routes) external payable returns (bytes32) {
        require(_sliceTokenQuantity > 0, "SliceToken: Slice token quantity can't be zero");

        require(_maxEstimatedPrices.length == _routes.length && _maxEstimatedPrices.length == positions.length, "SliceToken: Incorrect length for prices or routes");

        uint256 sumPrice = Utils.sumMaxEstimatedPrices(_maxEstimatedPrices);

        paymentToken.transferFrom(msg.sender, address(sliceCore), sumPrice);
        
        bytes32 mintId = keccak256(abi.encodePacked(this.mint.selector, msg.sender, address(this), _sliceTokenQuantity, sumPrice, block.timestamp));

        SliceTransactionInfo memory txInfo = SliceTransactionInfo(
            mintId,
            _sliceTokenQuantity,
            msg.sender,
            TransactionState.OPEN,
            bytes("")
        );

        mints[mintId] = txInfo;

        ISliceCore(sliceCore).purchaseUnderlyingAssets{value: msg.value}(mintId, _sliceTokenQuantity, _maxEstimatedPrices, _routes);

        return mintId;
    }

    /**
     * @dev See ISliceToken - mintComplete
     */
    function mintComplete(bytes32 _mintID) external onlySliceCore {
        // get transaction info
        SliceTransactionInfo memory _txInfo = mints[_mintID];

        // check that mint ID is valid
        require(_txInfo.id != bytes32(0), "SliceToken: Invalid mint ID");

        // check that state is open
        require(_txInfo.state == TransactionState.OPEN, "SliceToken: Transaction state is not open");

        // change transaction state to fulfilled
        mints[_mintID].state = TransactionState.FULFILLED;

        // mint X quantity of tokens to user
        _mint(_txInfo.user, _txInfo.quantity);

        // emit event
        emit SliceMinted(_txInfo.user, _txInfo.quantity);
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
    function redeem(uint256 _sliceTokenQuantity) external payable returns (bytes32) {
        // make sure the user has enough balance
        require(balanceOf(msg.sender) >= _sliceTokenQuantity, "SliceToken: Trying to redeem more than token balance");

        // lock the given amount of tokens in the users balance (can't be transferred)
        locked[msg.sender] += _sliceTokenQuantity;

        // create redeem ID
        bytes32 redeemID = keccak256(abi.encodePacked(this.redeem.selector, msg.sender, address(this), _sliceTokenQuantity, block.timestamp));

        // create tx info
        SliceTransactionInfo memory txInfo = SliceTransactionInfo(
            redeemID,
            _sliceTokenQuantity,
            msg.sender,
            TransactionState.OPEN,
            bytes("")
        );

        // record redeem ID + tx info
        redeems[redeemID] = txInfo;

        // call redeem underlying on slice core
        ISliceCore(sliceCore).redeemUnderlying{value: msg.value}(redeemID);

        // return redeem ID
        return redeemID;
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

    function verifyTransfer(address _sender, uint256 _amount) internal view returns (bool) {
        return balanceOf(_sender) - _amount >= locked[_sender];
    }
}
