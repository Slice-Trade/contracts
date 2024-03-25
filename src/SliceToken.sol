// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/ISliceToken.sol";

contract SliceToken is ISliceToken, ERC20 {
    address public sliceCore;
    Position[] public positions;

    modifier onlySliceCore() {
        require(msg.sender == sliceCore, "SliceToken: Only Slice Core can call");
        _;
    }

    constructor(string memory _name, string memory _symbol, Position[] memory _positions, address _sliceCore)
        ERC20(_name, _symbol)
    {
        sliceCore = _sliceCore;

        for (uint256 i = 0; i < _positions.length; i++) {
            positions.push(_positions[i]);
        }
    }

    /**
     * @dev See ISliceToken - mint
     */
    function mint(uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external {
        // TODO
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
    function rebalance(Position[] calldata _positions) external {
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
    function redeem(uint256 _sliceTokenQuantity) external {
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

    function getMintId(uint256 _idx) external view returns (bytes32) {
        // TODO
    }

    function getRebalanceId(uint256 _idx) external view returns (bytes32) {
        // TODO
    }

    function getRedeemId(uint256 _idx) external view returns (bytes32) {
        // TODO
    }
}
