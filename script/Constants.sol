// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Vm.sol";

contract Constants {
    mapping(string => address) public addressMap;
    mapping(string => bytes32) public pairCodeHash;

    string[] public addressKeys;

    constructor() {
        setAddress("sepolia.paymentToken", 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);
        setAddress("sepolia.sushiXSwap", 0x32F34391965A8e9322194edA50013af19b866227);
        setAddress("sepolia.stargateAdapter", 0xC2216FCdf9bb3a40D20eD2E17632fe5AdFd4aB63);
        setAddress("sepolia.axelarAdapter", 0x9d56C29Fc58F06B5846503C225C09090c8661BeF);
        setAddress("sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("sepolia.chainInfo", 0x3187F6AC207c6c58031Abc018d74399c0a8860AC);
        setAddress("sepolia.tokenDeployer", 0xaA00a929E78f73F63bfe208bFc0ac452F636b10e);

        setAddress("op_sepolia.paymentToken", 0x488327236B65C61A6c083e8d811a4E0D3d1D4268);
        setAddress("op_sepolia.sushiXSwap", 0x6C1aeA2C4933f040007a43Bc5683B0e068452c46);
        setAddress("op_sepolia.stargateAdapter", 0x2B798E5a0cE8018EDd5532fF4899E2f241271ab0);
        setAddress("op_sepolia.axelarAdapter", 0x58143BB43d57BfFAf4Ef47149a9be319D76c960b);
        setAddress("op_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("op_sepolia.chainInfo", 0xB1c883daf4ed666aa7caDC3f8dD0180addE0C3ba);
        setAddress("op_sepolia.tokenDeployer", 0x107EA81c7894305BE7179d3424A4C22684Dca961);
    }

    function initAddressLabels(Vm vm) public {
        for (uint256 i = 0; i < addressKeys.length; i++) {
            string memory key = addressKeys[i];
            vm.label(addressMap[key], key);
        }
    }

    function setAddress(string memory key, address value) public {
        require(addressMap[key] == address(0), string(bytes.concat("address already exists: ", bytes(key))));
        addressMap[key] = value;
        addressKeys.push(key);
    }

    function getAddress(string memory key) public view returns (address) {
        require(addressMap[key] != address(0), string(bytes.concat("address not found: ", bytes(key))));
        return addressMap[key];
    }

    function getPairCodeHash(string calldata key) public view returns (bytes32) {
        require(pairCodeHash[key] != "", string(bytes.concat("pairCodeHash not found: ", bytes(key))));
        return pairCodeHash[key];
    }
}
