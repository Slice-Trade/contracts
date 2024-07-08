// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ISliceCore} from "./interfaces/ISliceCore.sol";
import {ISliceToken} from "./interfaces/ISliceToken.sol";

import {TokenAmountUtils} from "./libs/TokenAmountUtils.sol";

import "./Structs.sol";

import "forge-std/src/console.sol";

/**
 * @author Lajos Deme, Blind Labs
 * @notice ERC20 contract providing exposure to a basket of underlying assets
 */
contract SliceToken is ISliceToken, ERC20, ReentrancyGuard {
    address public immutable sliceCore;
    Position[] public positions;
    mapping(address => uint256) public posIdx;

    string public category;
    string public description;

    mapping(bytes32 mintId => SliceTransactionInfo txInfo) public mints;
    mapping(bytes32 redeemId => SliceTransactionInfo txInfo) public redeems;

    mapping(address user => uint256 lockedAmount) public locked;

    mapping(address => uint256) public nonces;

    modifier onlySliceCore() {
        if (msg.sender != sliceCore) {
            revert NotSliceCore();
        }
        _;
    }

    constructor(string memory _name, string memory _symbol, Position[] memory _positions, address _sliceCore)
        ERC20(_name, _symbol)
    {
        if (_sliceCore == address(0)) revert SliceCoreNull();

        if (_positions.length == 0) revert PositionsEmpty();

        sliceCore = _sliceCore;

        for (uint256 i = 0; i < _positions.length; i++) {
            if (_positions[i].token == address(0)) revert InvalidTokenAddress();

            // check that each position's units are bigger than 1
            if (_positions[i].units < 10 ** _positions[i].decimals) {
                revert InsufficientPositionUnits();
            }

            // check that the positions are ordered by chain ID -> will make it easier to group signals by chainID in SliceCore.groupAndSendLzMsg
            if (i > 0 && _positions[i].chainId < _positions[i - 1].chainId) {
                revert UnorderedChainIds();
            }

            positions.push(_positions[i]);
            posIdx[_positions[i].token] = i;
        }
    }

    /* =========================================================== */
    /*   ===================    EXTERNAL   ====================    */
    /* =========================================================== */
    /**
     * @dev See ISliceToken - mint
     */
    function mint(uint256 sliceTokenQuantity, uint128[] calldata fees)
        external
        payable
        nonReentrant
        returns (bytes32)
    {
        verifySliceTokenQuantity(sliceTokenQuantity);

        uint256 nonce = nonces[msg.sender]++;

        bytes32 mintId = keccak256(
            abi.encodePacked(
                this.mint.selector, block.chainid, msg.sender, address(this), sliceTokenQuantity, block.timestamp, nonce
            )
        );

        SliceTransactionInfo memory txInfo = SliceTransactionInfo({
            id: mintId,
            quantity: sliceTokenQuantity,
            user: msg.sender,
            state: TransactionState.OPEN
        });

        mints[mintId] = txInfo;

        ISliceCore(sliceCore).collectUnderlying{value: msg.value}(mintId, fees);

        return mintId;
    }

    /**
     * @dev See ISliceToken - mintComplete
     */
    function mintComplete(bytes32 mintID) external onlySliceCore {
        // get transaction info
        SliceTransactionInfo memory _txInfo = mints[mintID];

        // check that mint ID is valid
        if (_txInfo.id != mintID || _txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        // check that state is open
        if (_txInfo.state != TransactionState.OPEN) {
            revert InvalidTransactionState();
        }

        // change transaction state to fulfilled
        mints[mintID].state = TransactionState.FULFILLED;

        // mint X quantity of tokens to user
        _mint(_txInfo.user, _txInfo.quantity);

        // emit event
        emit SliceMinted(_txInfo.user, _txInfo.quantity);
    }

    /**
     * @dev See ISliceToken - mintFailed
     */
    function mintFailed(bytes32 mintID) external onlySliceCore {
        SliceTransactionInfo memory _txInfo = mints[mintID];
        if (_txInfo.id != mintID || _txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        if (_txInfo.state == TransactionState.FAILED) {
            return;
        }

        if (_txInfo.state != TransactionState.OPEN) {
            revert InvalidTransactionState();
        }

        mints[mintID].state = TransactionState.FAILED;

        emit SliceMintFailed(_txInfo.user, _txInfo.quantity);
    }

    /**
     * @dev See ISliceToken - redeem
     */
    function redeem(uint256 sliceTokenQuantity, uint128[] calldata fees)
        external
        payable
        nonReentrant
        returns (bytes32)
    {
        verifySliceTokenQuantity(sliceTokenQuantity);

        // make sure the user has enough balance
        if (balanceOf(msg.sender) < sliceTokenQuantity) {
            revert InsufficientBalance();
        }

        // lock the given amount of tokens in the users balance (can't be transferred)
        locked[msg.sender] += sliceTokenQuantity;

        uint256 nonce = nonces[msg.sender]++;

        // create redeem ID
        bytes32 redeemID = keccak256(
            abi.encodePacked(
                this.redeem.selector,
                block.chainid,
                msg.sender,
                address(this),
                sliceTokenQuantity,
                block.timestamp,
                nonce
            )
        );

        // create tx info
        SliceTransactionInfo memory txInfo = SliceTransactionInfo({
            id: redeemID,
            quantity: sliceTokenQuantity,
            user: msg.sender,
            state: TransactionState.OPEN
        });

        // record redeem ID + tx info
        redeems[redeemID] = txInfo;

        // call redeem underlying on slice core
        ISliceCore(sliceCore).redeemUnderlying{value: msg.value}(redeemID, fees);

        // return redeem ID
        return redeemID;
    }

    /**
     * @dev See ISliceToken - redeemComplete
     */
    function redeemComplete(bytes32 redeemID) external onlySliceCore {
        // get transaction info
        SliceTransactionInfo memory _txInfo = redeems[redeemID];

        // check that redeem ID is valid
        if (_txInfo.id != redeemID || _txInfo.id == bytes32(0)) {
            revert RedeemIdDoesNotExist();
        }

        // check that state is open
        if (_txInfo.state != TransactionState.OPEN) {
            revert InvalidTransactionState();
        }

        // change transaction state to fulfilled
        redeems[redeemID].state = TransactionState.FULFILLED;

        // burn X quantity of tokens from user
        _burn(_txInfo.user, _txInfo.quantity);

        // remove lock on quantity
        locked[_txInfo.user] -= _txInfo.quantity;

        // emit event
        emit SliceRedeemed(_txInfo.user, _txInfo.quantity);
    }

    /**
     * @dev See ISliceToken - refund
     */
    function refund(bytes32 mintID, uint128[] calldata fees) external payable nonReentrant {
        SliceTransactionInfo memory _txInfo = mints[mintID];

        if (_txInfo.id != mintID || _txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }

        if (_txInfo.state != TransactionState.FAILED) {
            revert InvalidTransactionState();
        }

        _txInfo.state = TransactionState.REFUNDING;
        mints[mintID].state = _txInfo.state;

        ISliceCore(sliceCore).refund{value: msg.value}(_txInfo, fees);
    }

    /**
     * @dev See ISliceToken - refundComplete
     */
    function refundComplete(bytes32 mintID) external onlySliceCore {
        // get transaction info
        SliceTransactionInfo memory _txInfo = mints[mintID];
        if (_txInfo.id != mintID || _txInfo.id == bytes32(0)) {
            revert MintIdDoesNotExist();
        }
        if (_txInfo.state != TransactionState.REFUNDING) {
            revert InvalidTransactionState();
        }

        mints[mintID].state = TransactionState.REFUNDED;

        emit RefundCompleted(_txInfo.user, _txInfo.quantity);
    }

    function setCategoryAndDescription(string calldata _category, string calldata _description) external {
        if (bytes(category).length != 0 || bytes(description).length != 0) {
            revert AlreadySet();
        }

        category = _category;
        description = _description;
    }

    /* =========================================================== */
    /*   =================   EXTERNAL VIEW   ==================    */
    /* =========================================================== */
    /**
     * @dev See ISliceToken - getPositions
     */
    function getPositions() external view returns (Position[] memory) {
        return positions;
    }

    /**
     * @dev See ISliceToken - getNumberOfPositions
     */
    function getNumberOfPositions() external view returns (uint256) {
        return positions.length;
    }

    /**
     * @dev See ISliceToken - getMint
     */
    function getMint(bytes32 id) external view returns (SliceTransactionInfo memory) {
        return mints[id];
    }

    /**
     * @dev See ISliceToken - getRedeem
     */
    function getRedeem(bytes32 id) external view returns (SliceTransactionInfo memory) {
        return redeems[id];
    }

    /**
     * @dev See ISliceToken - getPosIdx
     */
    function getPosIdx(address underlyingAsset) external view returns (uint256) {
        return posIdx[underlyingAsset];
    }

    /**
     * @dev See ISliceToken - getPosAtIdx
     */
    function getPosAtIdx(uint256 idx) external view returns (Position memory) {
        if (idx >= positions.length) {
            revert("Invalid index");
        }
        return positions[idx];
    }

    /* =========================================================== */
    /*   =====================   PUBLIC   =====================    */
    /* =========================================================== */
    // before ERC20 transfer, check that the amount is not locked because of a pending redeem
    function transfer(address to, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        if (!verifyTransfer(msg.sender, amount)) {
            revert AmountLocked();
        }

        bool success = super.transfer(to, amount);
        return success;
    }

    /* =========================================================== */
    /*   ===================    INTERNAL   ====================    */
    /* =========================================================== */
    // verify that the amount is not locked becuase of a pending redeem
    function verifyTransfer(address _sender, uint256 _amount) internal view returns (bool) {
        return balanceOf(_sender) - _amount >= locked[_sender];
    }

    /* 
     * verify that the quantity the user wants to mint/redeem:
     *  - is not zero
     *  - for all positions the resulting position units won't be zero (required because of different position decimals)
     */
    function verifySliceTokenQuantity(uint256 _sliceTokenQuantity) internal view {
        if (_sliceTokenQuantity == 0) {
            revert ZeroTokenQuantity();
        }

        for (uint256 i = 0; i < positions.length; i++) {
            uint256 minPositionUnits = TokenAmountUtils.getMinimumAmountInSliceToken(positions[i].decimals);
            if (_sliceTokenQuantity < minPositionUnits) {
                revert InsufficientTokenQuantity();
            }
        }
    }
}
