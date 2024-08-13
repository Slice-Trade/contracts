// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library TokenAmountUtils {
    uint8 constant SLICE_TOKEN_DECIMALS = 18;

    /**
     * @dev calculates the amount of underlying asset to transfer for a given amount of slice tokens to mint
     * @param quantity The quantity of slice tokens we want to get out
     * @param units The units of the underlying assets we are providing
     * @param decimals The decimals of the underlying asset
     */
    function calculateAmountOutMin(uint256 quantity, uint256 units, uint8 decimals) internal pure returns (uint256) {
        quantity = convertSliceTokenDecimalsToOther(quantity, decimals);

        uint256 result = (units * quantity) / 10 ** decimals;

        return result;
    }

    /**
     * @dev calculates the amount of min slices tokens receiveable if the given amount of the underlying asset is transferred
     * @param inputUnits The amount of the underlying token we are providing
     * @param targetUnits The amount of units in the position of the slice token
     * @param decimals The decimals of the given position
     */
    function calculateAmountInMin(uint256 inputUnits, uint256 targetUnits, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        uint256 result = (inputUnits * 10 ** decimals) / targetUnits;
        return convertOtherDecimalsToSliceToken(result, decimals);
    }

    function getMinimumAmountInSliceToken(uint8 tokenBDecimals) internal pure returns (uint256) {
        if (SLICE_TOKEN_DECIMALS <= tokenBDecimals) {
            return 1;
        }

        uint8 difference = SLICE_TOKEN_DECIMALS - tokenBDecimals;
        return 10 ** difference;
    }

    function convertSliceTokenDecimalsToOther(uint256 amount, uint8 toDecimals) internal pure returns (uint256) {
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

    function convertOtherDecimalsToSliceToken(uint256 amount, uint8 fromDecimals) internal pure returns (uint256) {
        if (fromDecimals == SLICE_TOKEN_DECIMALS) {
            return amount;
        } else if (fromDecimals > SLICE_TOKEN_DECIMALS) {
            uint8 difference = fromDecimals - SLICE_TOKEN_DECIMALS;
            return amount / (10 ** difference);
        } else {
            uint8 difference = SLICE_TOKEN_DECIMALS - fromDecimals;
            return amount * (10 ** difference);
        }
    }
}
