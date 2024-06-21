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
        setAddress("eth_sepolia.chainInfo", 0x7951cAE82B68d21f7D424f3C95a454338c83a75d);
        setAddress("eth_sepolia.tokenDeployer", 0xc296967ed7A63037E1c42d7d4474F918742A62eb);

        setAddress("op_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("op_sepolia.chainInfo", 0xE106522FC3dada0fb089992fcf60877eA75aF9C1);
        setAddress("op_sepolia.tokenDeployer", 0xbf247aD0e89B5306cCbac0E2646FD86C16AF2d11);

        setAddress("base_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("base_sepolia.chainInfo", 0xDeac2A222cb36c2e035f3Ed36DF2dfb1cf675d74);
        setAddress("base_sepolia.tokenDeployer", 0x9fDa9f88a24F87E7c176e5F48AeDc69B3Ce16bF5);

        setAddress("arb_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("arb_sepolia.chainInfo", 0xfbB5eb88a4C99ae2C5b84184C84460f172f0eC06);
        setAddress("arb_sepolia.tokenDeployer", 0xB72B0771274Ca9a723816Baa775d7AA92d9533A9);

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
