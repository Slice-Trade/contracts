// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "forge-std/src/console.sol";
import {Position} from "../Structs.sol";
import {OraclePriceUpdate, Commitment} from "./CrossChainVaultStructs.sol";

library SliceTokenShareMath {
    error InvalidPositionsLength();

    uint256 constant SLICE_TOKEN_DECIMALS = 18;

    // calculates USA
    function calcAmountOfTokensReceiveable(uint256 userTokenShare, uint256 sliceTokenAmountMinted)
        internal
        pure
        returns (uint256)
    {
        return (userTokenShare * sliceTokenAmountMinted) / 1e18;
    }

    // calculates USS
    function calcUserTokenShare(uint256 totalUserCommVal, uint256 totalMintedSliceVal)
        internal
        pure
        returns (uint256)
    {
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

            if (positions[i].decimals < SLICE_TOKEN_DECIMALS) {
                usdValue = usdValue * (10**(SLICE_TOKEN_DECIMALS - positions[i].decimals));
            } else if (positions[i].decimals > SLICE_TOKEN_DECIMALS) {
                usdValue = usdValue / (10**(positions[i].decimals - SLICE_TOKEN_DECIMALS));
            }

            totalUsdvalue += usdValue;
        }
    }

    // calculates TSVUsd
    function calcTotalMintedSliceUSDValue(uint256 tsUsd, uint256 sMinted) internal pure returns (uint256) {
        return (tsUsd * sMinted) / 1e18;
    }

    // calculates TUC_usd
    function calcUserCommsTotalValue(
        Commitment[] memory _userCommitmentsForStrat,
        OraclePriceUpdate[] memory _priceUpdates
    ) internal pure returns (uint256) {
        uint256 commLength = _userCommitmentsForStrat.length;
        uint256 totalUserCommVal;

        for (uint256 i = 0; i < commLength; i++) {
            OraclePriceUpdate memory _priceUpdate = _priceUpdates[i];
            uint256 scaledPrice = _priceUpdate.price * (10 ** _userCommitmentsForStrat[i].decimals);

            uint256 usdValue = (_userCommitmentsForStrat[i].committed * scaledPrice)
                / (10 ** (_userCommitmentsForStrat[i].decimals + _priceUpdate.decimals));

            totalUserCommVal += usdValue;
        }

        return totalUserCommVal;
    }
}
