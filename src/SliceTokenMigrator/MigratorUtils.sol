// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library MigratorUtils {
    function sortAssets(address[] memory sliceAPositions, address[] memory sliceBPositions)
        public
        pure
        returns (address[] memory, address[] memory)
    {
        uint256 lengthA = sliceAPositions.length;
        uint256 lengthB = sliceBPositions.length;

        uint256 commonCount;
        uint256 inSliceACount;

        address[] memory common = new address[](lengthA);
        address[] memory inSliceA = new address[](lengthA);

        for (uint256 i = 0; i < lengthA; i++) {
            bool isCommon;
            for (uint256 j = 0; j < lengthB; j++) {
                if (sliceAPositions[i] == sliceBPositions[j]) {
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
}
