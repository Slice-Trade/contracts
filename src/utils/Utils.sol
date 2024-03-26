// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library Utils {
    function sumMaxEstimatedPrices(uint256[] memory _maxEstimatedPrices) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < _maxEstimatedPrices.length; i++) {
            sum += _maxEstimatedPrices[i];
        }
    }
}
