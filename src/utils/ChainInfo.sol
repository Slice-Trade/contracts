// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Structs.sol";
import "./Bytes32String.sol";

contract ChainInfo is Ownable {
    mapping(uint256 => Chain) public chains;

    constructor() Ownable(msg.sender) {
        // ethereum
        chains[1] = Chain(
            1,
            30101
        );

        //bnb
        chains[56] = Chain(
            56,
            30102
        );

        // avalance
        chains[43114] = Chain(
            43114,
            30106
        );

        // polygon
        chains[137] = Chain(
            137,
            30109
        );

        // arbitrum
        chains[42161] = Chain(
            42161,
            30110
        );

        // optimism
        chains[10] = Chain(
            10,
            30111
        );

        // base
        chains[8453] = Chain(
            8453,
            30184
        );

        // fantom
        chains[250] = Chain(
            250,
            30112
        );

        // linea
        chains[59144] = Chain(
            59144,
            30183
        );

        // kava
        chains[2222] = Chain(
            2222,
            30177
        );

        // metis
        chains[1088] = Chain(
            1088,
            30151
        );
    }

    function addChain(Chain memory _chain) external onlyOwner {
        require(chains[_chain.chainId].chainId == 0, "ChainInfo: Chain already registered");
        chains[_chain.chainId] = _chain;
    }

    function getChainInfo(uint256 _chainId) public view returns (Chain memory) {
        return chains[_chainId];
    }
}