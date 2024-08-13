// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Position} from "../Structs.sol";
import {OraclePriceUpdate, Commitment} from "./CrossChainVaultStructs.sol";

library SliceTokenShareMath {
    error InvalidPositionsLength();

    function calcAmountOfTokensReceived() internal pure returns (uint256) {
        
    }

    // calculates USS
    function calcUserTokenShare(uint256 totalUserCommVal, uint256 totalMintedSliceVal) internal pure returns (uint256) {
        if (totalMintedSliceVal == 0) {
            revert();
        }
        uint256 result = (totalUserCommVal * 1e18) / totalMintedSliceVal;
        return result;
    }

    // calculates TSusd
    function calcSliceTokenUSDValue(Position[] memory positions, OraclePriceUpdate[] memory positionUsdPrices)
        internal
        pure
        returns (uint256 totalUsdvalue)
    {
        uint256 posLength = positions.length;
        if (posLength != positionUsdPrices.length) {
            revert InvalidPositionsLength();
        }

        for (uint256 i = 0; i < posLength; i++) {
            uint256 scaledPrice = positionUsdPrices[i].price * (10 ** positions[i].decimals);
            uint256 usdValue =
                (positions[i].units * scaledPrice) / (10 ** (positions[i].decimals + positionUsdPrices[i].decimals));

            totalUsdvalue += usdValue;
        }
    }

    // calculates TSVUsd
    function calcTotalMintedSliceUSDValue(uint256 tsUsd, uint256 sMinted) internal pure returns (uint256) {
        return tsUsd * sMinted;
    }
}
