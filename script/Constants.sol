// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Vm.sol";

contract Constants {
    mapping(string => address) public addressMap;
    mapping(string => uint) public uintMap;
    mapping(uint => uint) public uintMap2;

    string[] public addressKeys;
    string[] public uintKeys;
    uint[] public uintKeys2;

    constructor() {
        setAddress("owner", 0x1c46D242755040a0032505fD33C6e8b83293a332);
        setAddress("owner.mainnet", 0xe2A26fABb6918540180CFe1aD65F357928c4132A);

        setAddress("deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);

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
        
        setAddress("scroll_sepolia.lzEndpoint", 0x6EDCE65403992e310A62460808c4b910D972f10f);
        setAddress("scroll_sepolia.chainInfo", 0xBFC2610542C7bcC56eBF526eD95b271a1015F1D1);
        setAddress("scroll_sepolia.tokenDeployer", 0x9BAD40cD7c4d8Fb9b66778B1eAc02B14552E8b41);

        setAddress("arb.lzEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
        setAddress("arb.chainInfo", 0xa049c6cBF3348e509fc3B086CA11dB908Bc7ca79);
        setAddress("arb.tokenDeployer", 0x784D6CF65f4BCd516eC73780701CEC1E1Ffe4c3B);
        
        setAddress("op.lzEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
        setAddress("op.chainInfo", 0xa049c6cBF3348e509fc3B086CA11dB908Bc7ca79);
        setAddress("op.tokenDeployer", 0x784D6CF65f4BCd516eC73780701CEC1E1Ffe4c3B );
        
        setAddress("base.lzEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
        setAddress("base.chainInfo", 0x8004Ae017e65E2D0c45A9f8d1d352b3012C88e8e);
        setAddress("base.tokenDeployer",  0xA36301510939cf30033303417c9B95f200Ef4EB6);

        setUint("ETH_SEPOLIA_CHAIN_ID", 11155111);
        setUint("OP_SEPOLIA_CHAIN_ID", 11155420);
        setUint("BASE_SEPOLIA_CHAIN_ID", 84532);
        setUint("ARB_SEPOLIA_CHAIN_ID", 84532);
        setUint("SCROLL_SEPOLIA_CHAIN_ID", 534351);

        setUint("ARB_CHAIN_ID", 42161);
        setUint("OP_CHAIN_ID", 10);
        setUint("BASE_CHAIN_ID", 8453);

        setUint(42161, 30110); // layer zero endpoint ID for Arbitrum
        setUint(10, 30111); // layer zero endpoint ID for Optimism
        setUint(8453, 30184); // layer zero endpoint ID for Base

        // TESTNET LZ EIDs
        setUint(11155111, 40161); // sepolia
        setUint(11155420, 40232); //op sepolia
        setUint(84532, 40245); // base sepolia
        setUint(421614, 40231); //arb sepolia
        setUint(534351, 40170); //arb sepolia
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

    function setUint(string memory key, uint value) public {
        require(uintMap[key] == 0, string(bytes.concat("uint already exists: ", bytes(key))));
        uintMap[key] = value;
        uintKeys.push(key);
    }

    function getUint(string memory key) public view returns (uint) {
        require(uintMap[key] != 0, string(bytes.concat("uint not found: ", bytes(key))));
        return uintMap[key];
    }

    function setUint(uint key, uint value) public {
        require(uintMap2[key] == 0, string(bytes.concat("uint already exists: ", bytes32(key))));
        uintMap2[key] = value;
        uintKeys2.push(key);
    }

    function getUint(uint key) public view returns (uint) {
        require(uintMap2[key] != 0, string(bytes.concat("uint not found: ", bytes32(key))));
        return uintMap2[key];
    }
}
