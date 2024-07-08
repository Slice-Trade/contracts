// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library TokenAmountUtils {
    uint8 constant SLICE_TOKEN_DECIMALS = 18;

    function calculateAmountOutMin(uint256 quantity, uint256 units, uint8 decimals) internal pure returns (uint256) {
        quantity = convertDecimals(quantity, decimals);

        uint256 result = (units * quantity) / 10**decimals;
        
        return result;
    }

    function getMinimumAmountInSliceToken(uint8 tokenBDecimals) internal pure returns (uint256) {
        if (SLICE_TOKEN_DECIMALS <= tokenBDecimals) {
            return 1;
        }

        uint8 difference = SLICE_TOKEN_DECIMALS - tokenBDecimals;
        return 10 ** difference;
    }

    function convertDecimals(uint256 amount, uint8 toDecimals) internal pure returns (uint256) {
        if (SLICE_TOKEN_DECIMALS == toDecimals) {
            return amount;
        } else if (SLICE_TOKEN_DECIMALS > toDecimals) {
            uint8 difference = SLICE_TOKEN_DECIMALS - toDecimals;
            return amount / (10 ** difference);
        } else {
            uint8 difference = toDecimals - SLICE_TOKEN_DECIMALS;
            return amount * (10 ** difference);
        }
    }
}