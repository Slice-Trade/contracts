// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/Structs.sol";
import "../../src/interfaces/ISliceToken.sol";

contract SliceCoreMock {
    /** @dev See ISliceCore - purchaseUnderlyingAssets */
    function purchaseUnderlyingAssets(bytes32 _mintID, uint256 _sliceTokenQuantity, uint256 _maxEstimatedPrice) external {
        // TODO
    }

    /** @dev See ISliceCore - rebalanceUnderlying */
    function rebalanceUnderlying(bytes32 _rebalanceID, Position[] calldata _positions) external {
        // TODO
    }

    /** @dev See ISliceCore - redeemUnderlying */
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