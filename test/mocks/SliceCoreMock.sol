// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/Structs.sol";
import "../../src/interfaces/ISliceToken.sol";
import "../../src/external/IWETH.sol";

contract SliceCoreMock {
    address public token;

    IERC20 public usdc;
    IWETH public weth;
    IERC20 public wbtc;
    IERC20 public link;

    constructor(IERC20 _usdc, IWETH _weth, IERC20 _wbtc, IERC20 _link) {
        usdc = _usdc;
        weth = _weth;
        wbtc = _wbtc;
        link = _link;
    }

    function setToken(address _token) external {
        token = _token;
    } 

    /**
     * @dev See ISliceCore - purchaseUnderlyingAssets
     */
    function purchaseUnderlyingAssets(
        bytes32 _mintID,
        uint256 _sliceTokenQuantity,
        uint256[] memory _maxEstimatedPrices,
        bytes[] memory _routes
    ) external {
        require(_maxEstimatedPrices.length == 3, "Positions must be weth, btc, link");
        weth.transfer(token, 100000000000000000);
        wbtc.transfer(token, 10000000000000000);
        link.transfer(token, 20000000000000000000);
    }

    /**
     * @dev See ISliceCore - rebalanceUnderlying
     */
    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external {
        // TODO
    }

    /**
     * @dev See ISliceCore - redeemUnderlying
     */
    function redeemUnderlying(bytes32 _redeemID, SliceTransactionInfo memory _txInfo) external {
        // TODO
    }

    function mintComplete(bytes32 _mintID, address _sliceToken) external {
        ISliceToken(_sliceToken).mintComplete(_mintID);
    }

    function rebalanceComplete(bytes32 _rebalanceID, address _sliceToken) external {
        ISliceToken(_sliceToken).rebalanceComplete(_rebalanceID);
    }

    function redeemComplete(bytes32 _redeemID, address _sliceToken) external {
        ISliceToken(_sliceToken).redeemComplete(_redeemID);
    }
}
