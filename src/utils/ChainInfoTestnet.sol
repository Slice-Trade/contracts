// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Structs.sol";

contract ChainInfo is Ownable {
    mapping(uint256 => Chain) public chains;

    constructor() Ownable(msg.sender) {
        // sepolia
        chains[11155111] = Chain(11155111, 40161);

        // OP Sepolia
        chains[11155420] = Chain(11155420, 40232);

        // Base Sepolia
        chains[84532] = Chain(84532, 40245);

        // Arbitrum Sepolia
        chains[421614] = Chain(421614, 40231);

        // Scroll Sepolia
        chains[534351] = Chain(534351, 40170);
    }

    function addChain(Chain memory _chain) external onlyOwner {
        require(chains[_chain.chainId].chainId == 0, "ChainInfo: Chain already registered");
        chains[_chain.chainId] = _chain;
    }

    function getChainInfo(uint256 _chainId) public view returns (Chain memory) {
        return chains[_chainId];
    }
}
