// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/external/ISushiXSwapV2.sol";

contract SushiXSwapMock is ISushiXSwapV2 {
    // TODO: This mock contract will help us test swaps and bridging
    // Will deal some of the given token to the given address when the correct SushiXSwap function is called
    uint256 constant MAX_ESTIMATED_PRICE = 1355000000;

    function rp() external view returns (IRouteProcessor) {
        // TODO
    }

    function swap(bytes memory _swapData) external payable {
        // TODO
    }

    function bridge(
        BridgeParams calldata _bridgeParams,
        address _refundAddress,
        bytes calldata _swapPayload,
        bytes calldata _payloadData
    ) external payable {
        // TODO
    }

    function sendMessage(
        address _adapter,
        bytes calldata _adapterData
    ) external payable {
        // TODO
    }

    function swapAndBridge(
        BridgeParams calldata _bridgeParams,
        address _refundAddress,
        bytes calldata _swapData,
        bytes calldata _swapPayload,
        bytes calldata _payloadData
    ) external payable {
        // only needed for interface, not used in mock
    }

    function updateAdapterStatus(address _adapter, bool _status) external {
        // only needed for interface, not used in mock
    }

    function updateRouteProcessor(address newRouteProcessor) external {
        // only needed for interface, not used in mock
    }


}