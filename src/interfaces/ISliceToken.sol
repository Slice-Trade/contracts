// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Structs.sol";

interface ISliceToken is IERC20 {
    event SliceMinted(address indexed to, uint256 indexed amount);

    event SliceRebalanced(address indexed token);

    event SliceRedeemed(address indexed to, uint256 indexed amount);

    function mint(uint256 _amount) external;

    function mintComplete(bytes32 _mintID) external;

    function rebalance(Position[] calldata _positions) external;

    function rebalanceComplete(bytes32 _rebalanceID) external;

    function redeem(uint256 _amount) external;

    function redeemComplete(bytes32 _redeemID) external;

    function getPositions() external view returns (Position[] memory);
}