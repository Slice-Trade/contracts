// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/Structs.sol";
import "../../src/interfaces/ISliceToken.sol";
import "../../src/external/IWETH.sol";

contract SliceCoreMock {
    address public token;

    IERC20 public usdc;
    IWETH public weth;
    IERC20 public wbtc;
    IERC20 public link;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public wbtcUnits = 100000000; // 1 wBTC (8 decimals)
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    constructor(IERC20 _usdc, IWETH _weth, IERC20 _link) {
        usdc = _usdc;
        weth = _weth;
        link = _link;
    }

    function setToken(address _token) external {
        token = _token;
    }

    /**
     * @dev See ISliceCore - purchaseUnderlyingAssets
     */
    function collectUnderlying(bytes32 _mintID, uint128[] memory fees) external payable {}

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 _redeemID, uint128[] memory fees) external {}

    function mintComplete(bytes32 _mintID, address _sliceToken) external {
        ISliceToken(_sliceToken).mintComplete(_mintID);
    }

    function redeemComplete(bytes32 _redeemID, address _sliceToken) external {
        ISliceToken(_sliceToken).redeemComplete(_redeemID);
    }
}
