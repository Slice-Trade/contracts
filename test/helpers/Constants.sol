// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/src/Vm.sol";
import "forge-std/src/console.sol";

contract Constants {
  mapping(string => address) public addressMap;
  mapping(string => bytes32) public pairCodeHash;
  //byteCodeHash for trident pairs

  string[] public addressKeys;

  constructor() {
    // Mainnet
    setAddress("mainnet.weth", 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    setAddress("mainnet.sushi", 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    setAddress("mainnet.usdc", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    setAddress("mainnet.usdt", 0xdAC17F958D2ee523a2206206994597C13D831ec7);
    setAddress("mainnet.wbtc", 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    setAddress("mainnet.link", 0x514910771AF9Ca656af840dff83E8264EcF986CA);

    setAddress("mainnet.layerZeroEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
    
    setAddress("mainnet.routeProcessor", 0x827179dD56d07A7eeA32e3873493835da2866976);
    setAddress("mainnet.v2Factory", 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    setAddress("mainnet.v3Factory", 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F);

    setAddress("mainnet.deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);
    setAddress("polygon.deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);
    setAddress("optimism.deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);

    setAddress("polygon.usdc", 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    setAddress("polygon.layerZeroEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
    setAddress("optimism.layerZeroEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
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