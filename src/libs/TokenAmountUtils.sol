// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library TokenAmountUtils {
    function calculateAmountOutMin(uint256 quantity, uint256 units, uint8 decimals) internal pure returns (uint256) {
        quantity = convertDecimals(quantity, decimals);

        uint256 result = (units * quantity) / 10**decimals;
        
        return result;
    }

    function getMinimumAmountInSliceToken(uint8 tokenBDecimals) internal pure returns (uint256) {
        uint8 tokenADecimals = 18;
        if (tokenADecimals <= tokenBDecimals) {
            return 1;
        }

        uint8 difference = tokenADecimals - tokenBDecimals;
        return 10 ** difference;
    }

    function convertDecimals(uint256 amount, uint8 toDecimals) internal pure returns (uint256) {
        uint8 fromDecimals = 18;
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            uint8 difference = fromDecimals - toDecimals;
            return amount / (10 ** difference);
        } else {
            uint8 difference = toDecimals - fromDecimals;
            return amount * (10 ** difference);
        }
    }
}