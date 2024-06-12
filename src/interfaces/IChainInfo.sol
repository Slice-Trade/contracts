// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Structs.sol";

/// @notice This contract is used to store and retrieve information about a blockchain
interface IChainInfo {
    /**
     * @dev Adds a new chain to recorded chains
     *
     * @param _chain The chain to record
     */
    function addChain(Chain memory _chain) external;

    /**
     * @dev Returns the recoded chain info for a chain ID
     *
     * @param _chainId The chain ID to return the recorded chain info for
     */
    function getChainInfo(uint256 _chainId) external view returns (Chain memory);
}