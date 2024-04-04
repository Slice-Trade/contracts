// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Structs.sol";
import "./Bytes32String.sol";

contract ChainInfo is Ownable {
    mapping(uint256 => Chain) public chains;

    constructor() Ownable(msg.sender) {
        // sepolia
        chains[11155111] = Chain(
            11155111, 
            StringToBytes32.toBytes32("ethereum-sepolia"), 
            10161, 
            40161,
            0xC2216FCdf9bb3a40D20eD2E17632fe5AdFd4aB63,
            0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);

        // OP Sepolia
        chains[11155420] = Chain(
            11155420, 
            StringToBytes32.toBytes32("optimism-sepolia"), 
            10232, 
            40232,
            0x2B798E5a0cE8018EDd5532fF4899E2f241271ab0,
            0x488327236B65C61A6c083e8d811a4E0D3d1D4268);
    }

    function addChain(Chain memory _chain) external onlyOwner {
        require(chains[_chain.chainId].chainId == 0, "ChainInfo: Chain already registered");
        chains[_chain.chainId] = _chain;
    }

    function getChainInfo(uint256 _chainId) public view returns (Chain memory) {
        return chains[_chainId];
    }
}
