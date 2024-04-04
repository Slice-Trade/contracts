// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IStargateAdapter {
    /// @notice Get the fees to be paid in native token for the swap
    /// @param _dstChainId stargate dst chainId
    /// @param _functionType stargate Function type 1 for swap.
    /// See more at https://stargateprotocol.gitbook.io/stargate/developers/function-types
    /// @param _receiver receiver on the dst chain
    /// @param _gas extra gas being sent
    /// @param _dustAmount dust amount to be received at the dst chain
    /// @param _payload payload being sent at the dst chain
    function getFee(
        uint16 _dstChainId,
        uint8 _functionType,
        address _receiver,
        uint256 _gas,
        uint256 _dustAmount,
        bytes memory _payload
    ) external view returns (uint256 a, uint256 b);
}