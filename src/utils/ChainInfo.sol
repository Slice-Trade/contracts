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
            30101,
            0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0
        );

        //bnb
        chains[56] = Chain(
            56,
            StringToBytes32.toBytes32("binance"),
            102,
            30102,
            0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6
        );

        // avalance
        chains[43114] = Chain(
            43114,
            StringToBytes32.toBytes32("Avalanche"),
            106,
            30106,
            0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6
        );

        // polygon
        chains[137] = Chain(
            137,
            StringToBytes32.toBytes32("Polygon"),
            109,
            30109,
            0xFF51a7C624Eb866917102707F3dA8bFb99Db8692
        );

        // arbitrum
        chains[42161] = Chain(
            42161,
            StringToBytes32.toBytes32("arbitrum"),
            110,
            30110,
            0x2ABf469074dc0b54d793850807E6eb5Faf2625b1
        );

        // optimism
        chains[10] = Chain(
            10,
            StringToBytes32.toBytes32("optimism"),
            111,
            30111,
            0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6
        );

        // base
        chains[8453] = Chain(
            8453,
            StringToBytes32.toBytes32("base"),
            184,
            30184,
            0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0
        );

        // fantom
        chains[250] = Chain(
            250,
            StringToBytes32.toBytes32("Fantom"),
            112,
            30112,
            0x2ABf469074dc0b54d793850807E6eb5Faf2625b1
        );

        // linea
        chains[59144] = Chain(
            59144,
            StringToBytes32.toBytes32("linea"),
            183,
            30183,
            0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6
        );

        // kava
        chains[2222] = Chain(
            2222,
            StringToBytes32.toBytes32("kava"),
            177,
            30177,
            0xDf1cfEc0DCF05bf647FbfbE12ea550Baa102E195
        );

        // metis
        chains[1088] = Chain(
            1088,
            bytes32(0),
            151,
            30151,
            0xA62eC622DbA415Aa94110739B1f951B1202Cf322
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