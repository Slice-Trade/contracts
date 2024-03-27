// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Structs.sol";
import "./Bytes32String.sol";

contract ChainInfo is Ownable {
    mapping(uint256 => Chain) public chains;

    constructor() Ownable(msg.sender) {
        // ethereum
        chains[1] = Chain(
            1,
            StringToBytes32.toBytes32("Ethereum"),
            101,
            30101
        );

        //bnb
        chains[56] = Chain(
            56,
            StringToBytes32.toBytes32("binance"),
            102,
            30102
        );

        // avalance
        chains[43114] = Chain(
            43114,
            StringToBytes32.toBytes32("Avalanche"),
            106,
            30106
        );

        // polygon
        chains[137] = Chain(
            137,
            StringToBytes32.toBytes32("Polygon"),
            109,
            30109
        );

        // arbitrum
        chains[42161] = Chain(
            42161,
            StringToBytes32.toBytes32("arbitrum"),
            110,
            30110
        );

        // optimism
        chains[10] = Chain(
            10,
            StringToBytes32.toBytes32("optimism"),
            111,
            30111
        );

        // base
        chains[8453] = Chain(
            8453,
            StringToBytes32.toBytes32("base"),
            184,
            30184
        );

        // fantom
        chains[250] = Chain(
            250,
            StringToBytes32.toBytes32("Fantom"),
            112,
            30112
        );

        // linea
        chains[59144] = Chain(
            59144,
            StringToBytes32.toBytes32("linea"),
            183,
            30183
        );

        // kava
        chains[2222] = Chain(
            2222,
            StringToBytes32.toBytes32("kava"),
            177,
            30177
        );

        // metis
        chains[1088] = Chain(
            1088,
            bytes32(0),
            151,
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