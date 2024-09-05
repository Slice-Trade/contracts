// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Position} from "../Structs.sol";
import {MigratePosition} from "./MigratorStructs.sol";

library MigratorUtils {
    function sortAssets(Position[] memory sliceAPositions, Position[] memory sliceBPositions)
        public
        pure
        returns (Position[] memory, Position[] memory)
    {
        uint256 lengthA = sliceAPositions.length;
        uint256 lengthB = sliceBPositions.length;

        uint256 commonCount;
        uint256 inSliceACount;

        Position[] memory common = new Position[](lengthA);
        Position[] memory inSliceA = new Position[](lengthA);

        for (uint256 i = 0; i < lengthA; i++) {
            bool isCommon;
            for (uint256 j = 0; j < lengthB; j++) {
                if (sliceAPositions[i].token == sliceBPositions[j].token) {
                    common[commonCount] = sliceAPositions[i];
                    ++commonCount;
                    isCommon = true;
                    break;
                }
            }

            if (!isCommon) {
                inSliceA[inSliceACount] = sliceAPositions[i];
                ++inSliceACount;
            }
        }

        assembly {
            mstore(common, commonCount)
            mstore(inSliceA, inSliceACount)
        }

        return (common, inSliceA);
    }

    function getCommonAssets(Position[] memory sliceAPositions, Position[] memory sliceBPositions)
        public
        pure
        returns (MigratePosition[] memory)
    {
        uint256 lengthA = sliceAPositions.length;
        uint256 lengthB = sliceBPositions.length;

        uint256 commonCount;

        MigratePosition[] memory common = new MigratePosition[](lengthA);

        for (uint256 i = 0; i < lengthA; i++) {
            for (uint256 j = 0; j < lengthB; j++) {
                if (sliceAPositions[i].token == sliceBPositions[j].token) {
                    common[commonCount] = MigratePosition({
                        chainId: sliceAPositions[i].chainId,
                        token: sliceAPositions[i].token,
                        decimals: sliceAPositions[i].decimals,
                        unitsA: sliceAPositions[i].units,
                        unitsB: sliceBPositions[j].units
                    });
                    ++commonCount;
                    break;
                }
            }
        }

        assembly {
            mstore(common, commonCount)
        }

        return common;
    }

    function getSliceAOnlyAssets(Position[] memory sliceAPositions, Position[] memory sliceBPositions)
        public
        pure
        returns (Position[] memory)
    {
        uint256 lengthA = sliceAPositions.length;
        uint256 lengthB = sliceBPositions.length;

        uint256 sliceACount;

        Position[] memory inSliceA = new Position[](lengthA);

        for (uint256 i = 0; i < lengthA; i++) {
            bool isCommon;
            for (uint256 j = 0; j < lengthB; j++) {
                if (sliceAPositions[i].token == sliceBPositions[j].token) {
                    isCommon = true;
                    break;
                }
            }

            if (!isCommon) {
                inSliceA[sliceACount] = sliceAPositions[i];
                ++sliceACount;
            }
        }

        assembly {
            mstore(inSliceA, sliceACount)
        }

        return inSliceA;
    }
}
