// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Vm.sol";

contract Constants {
    mapping(string => address) public addressMap;
    mapping(string => bytes32) public pairCodeHash;

    string[] public addressKeys;

    constructor() {
        setAddress("owner", 0x1c46D242755040a0032505fD33C6e8b83293a332);

        setAddress("eth_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("eth_sepolia.chainInfo", 0x3187F6AC207c6c58031Abc018d74399c0a8860AC);
        setAddress("eth_sepolia.tokenDeployer", 0xDe959E0c6720Bb8f44DC73e85ce63AB219D4600d);

        setAddress("op_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("op_sepolia.chainInfo", 0xE106522FC3dada0fb089992fcf60877eA75aF9C1);
        setAddress("op_sepolia.tokenDeployer", 0xFbfD7D214f9F35053f5A7767f6a9DA7758d75f83);

        setAddress("base_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("base_sepolia.chainInfo", 0xDeac2A222cb36c2e035f3Ed36DF2dfb1cf675d74);
        setAddress("base_sepolia.tokenDeployer", 0x57e90c157D93317AF480632231068202a088687B);

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
