// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Structs.sol";

interface IChainInfo {
    function addChain(Chain memory _chain) external;
    function getChainInfo(uint256 _chainId) external view returns (Chain memory);
}