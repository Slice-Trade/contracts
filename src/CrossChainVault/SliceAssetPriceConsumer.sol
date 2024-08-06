// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../external/AggregatorV2V3Interface.sol";

contract SliceAssetPriceConsumer {
    mapping(address sliceToken => AggregatorV2V3Interface[] clPriceFeeds) public priceFeeds;

    function getLatestPriceInfo(address sliceToken) public view returns (int256[] memory) {
        AggregatorV2V3Interface[] memory _priceFeeds = priceFeeds[sliceToken];

        uint256 len = _priceFeeds.length;

        int256[] memory _priceInfos = new int256[](_priceFeeds.length);

        for (uint256 i = 0; i < len; i++) {
            (
                /* uint80 roundID */
                ,
                int256 answer,
                /*uint startedAt*/
                ,
                /*uint timeStamp*/
                ,
                /*uint80 answeredInRound*/
            ) = _priceFeeds[i].latestRoundData();

            _priceInfos[i] = answer;
        }

        return _priceInfos;
    }
}
