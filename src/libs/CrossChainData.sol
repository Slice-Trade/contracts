// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


import {OptionsBuilder} from "@lz-oapp-v2/libs/OptionsBuilder.sol";
import "../external/IRouteProcessor.sol";
import "../external/ISushiXSwapV2.sol";
import "../external/ISushiXSwapV2Adapter.sol";
import "../external/IStargateAdapter.sol";
import "../Structs.sol";

library CrossChainData {
    using OptionsBuilder for bytes;

    struct AdapterDataCreateInput {
        uint256 maxEstimatedPrice;
        uint256 gasForSwap;
        address paymentToken;
        address partnerSliceCore;
    }

    // assuming 18 decimals... TODO: Do with other decimals
    function calculateAmountOutMin(uint256 quantity, uint256 units) public pure returns (uint256) {
        uint256 result = (units * quantity) / 1 ether;
        return result;
    }

    function createLzSendOpts(uint128 _gas, uint128 _value) public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }

    function createAdapterData(Chain memory _dstChain, AdapterDataCreateInput memory _adapterDataInput)
        public
        pure
        returns (bytes memory _adapterData)
    {
        _adapterData = abi.encode(
            _dstChain.stargateChainId, // dst chain stargate id
            _adapterDataInput.paymentToken, // token in
            1, // src pool id - USDC
            1, // dst pool id - USDC
            _adapterDataInput.maxEstimatedPrice, // amount,
            0, // amountMin,
            0, // dust
            _dstChain.stargateAdapter, // receiver
            _adapterDataInput.partnerSliceCore, // to
            _adapterDataInput.gasForSwap // gas
        );
    }

    function createRouteProcessorDataEncoded(
        Chain memory _chainInfo,
        address _token,
        uint256 amountOutMin,
        address _partnerSliceCore,
        bytes memory _route
    ) public pure returns (bytes memory) {
        return abi.encode(
            IRouteProcessor.RouteProcessorData({
                tokenIn: _chainInfo.paymentToken,
                amountIn: 0, // amount in doesnt matter since we use amount bridged
                tokenOut: _token,
                amountOutMin: amountOutMin,
                to: _partnerSliceCore,
                route: _route
            })
        );
    }

    function getGasNeeded(
        uint16 stargateChainId,
        address stargateAdapter,
        address partnerSliceCore,
        bytes memory swapDataEncoded,
        bytes memory payloadDataEncoded
    ) public view returns (uint256) {
        (uint256 gasNeeded,) = IStargateAdapter(stargateAdapter).getFee(
            stargateChainId,
            1,
            stargateAdapter,
            550000,
            0,
            abi.encode(
                partnerSliceCore, // to
                swapDataEncoded, // swap data
                payloadDataEncoded // payload data
            )
        );

        return gasNeeded;
    }

    function createPayloadDataEncoded(
        bytes32 _mintId,
        address _token,
        uint256 amountOutMin,
        address _partnerSliceCore,
        uint256 _payloadGas,
        bytes memory _data
    ) public view returns (bytes memory) {
        return abi.encode(
            ISushiXSwapV2Adapter.PayloadData(
                _partnerSliceCore,
                _payloadGas, // TODO verify gas
                abi.encode(
                    SlicePayloadData(
                        block.chainid, // src chain id
                        _mintId, //mint ID
                        _token, // token Out
                        amountOutMin, // amount out min
                        _data // data
                    )
                ) // slice payload data
            )
        );
    }
}
