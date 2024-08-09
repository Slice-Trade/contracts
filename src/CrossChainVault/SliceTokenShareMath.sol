// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Position} from "../Structs.sol";
import {OraclePriceUpdate} from "./CrossChainVaultStructs.sol";

library SliceTokenShareMath {
    error InvalidPositionsLength();

    function calcAmountOfTokensReceived() internal pure returns (uint256) {}

    function calcUserTokenShare() internal pure returns (uint256) {}

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

    function calcTotalMintedSliceUSDValue() internal pure returns (uint256) {}

    function calcUserCommsTotalValue() internal pure returns (uint256) {}
}
