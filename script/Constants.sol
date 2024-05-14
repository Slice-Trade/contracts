// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Vm.sol";

contract Constants {
    mapping(string => address) public addressMap;
    mapping(string => bytes32) public pairCodeHash;

    string[] public addressKeys;

    constructor() {
        setAddress("owner", 0x1c46D242755040a0032505fD33C6e8b83293a332);

        setAddress("eth_sepolia.paymentToken", 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);
        setAddress("eth_sepolia.sushiXSwap", 0x32F34391965A8e9322194edA50013af19b866227);
        setAddress("eth_sepolia.stargateAdapter", 0xC2216FCdf9bb3a40D20eD2E17632fe5AdFd4aB63);
        setAddress("eth_sepolia.axelarAdapter", 0x9d56C29Fc58F06B5846503C225C09090c8661BeF);
        setAddress("eth_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("eth_sepolia.chainInfo", 0x3187F6AC207c6c58031Abc018d74399c0a8860AC);
        setAddress("eth_sepolia.tokenDeployer", 0xDe959E0c6720Bb8f44DC73e85ce63AB219D4600d);

        setAddress("op_sepolia.paymentToken", 0x488327236B65C61A6c083e8d811a4E0D3d1D4268);
        setAddress("op_sepolia.sushiXSwap", 0x6C1aeA2C4933f040007a43Bc5683B0e068452c46);
        setAddress("op_sepolia.stargateAdapter", 0x2B798E5a0cE8018EDd5532fF4899E2f241271ab0);
        setAddress("op_sepolia.axelarAdapter", 0x58143BB43d57BfFAf4Ef47149a9be319D76c960b);
        setAddress("op_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("op_sepolia.chainInfo", 0xB1c883daf4ed666aa7caDC3f8dD0180addE0C3ba);
        setAddress("op_sepolia.tokenDeployer", 0x54B57d418444d853ddC444409F46E925083541ad);

        setAddress("base_sepolia.paymentToken", 0x254d06f33bDc5b8ee05b2ea472107E300226659A);
        setAddress("base_sepolia.sushiXSwap", 0xbb23a54dde3054b8A458E17781393F30ad228e6C);
        setAddress("base_sepolia.stargateAdapter", 0x58A77ef8Fdb36a891825aa04464beD1511832bE7);
        setAddress("base_sepolia.axelarAdapter", 0x9AD840B246e09a5d093842a625D3Ec5991b73282);
        setAddress("base_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("base_sepolia.chainInfo", 0x0183D7C825fD3575E9a09a5df5684eA415884407);
        setAddress("base_sepolia.tokenDeployer", 0x9BAD40cD7c4d8Fb9b66778B1eAc02B14552E8b41);

        setAddress("deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);
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
