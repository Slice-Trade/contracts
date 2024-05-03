// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

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

    setAddress("mainnet.sushiXSwap", 0x804b526e5bF4349819fe2Db65349d0825870F8Ee);

    setAddress("mainnet.layerZeroEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);

    setAddress("mainnet.stargateAdapter", 0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0);
    setAddress("mainnet.axelarAdapter", 0x5AbEdAc449A8301467c3e124B98e7151641F1e56);
    
    setAddress("mainnet.routeProcessor", 0x827179dD56d07A7eeA32e3873493835da2866976);
    setAddress("mainnet.v2Factory", 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    setAddress("mainnet.v3Factory", 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F);

    setAddress("mainnet.stargateComposer", 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9);
    setAddress("mainnet.stargateWidget", 0x76d4d68966728894961AA3DDC1d5B0e45668a5A6);
    setAddress("mainnet.stargateFactory", 0x06D538690AF257Da524f25D0CD52fD85b1c2173E);
    setAddress("mainnet.stargateFeeLibrary", 0x8C3085D9a554884124C998CDB7f6d7219E9C1e6F);
    setAddress("mainnet.sgeth", 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c);
    setAddress("mainnet.stargateUSDCPool", 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);
    setAddress("mainnet.stargateETHPool", 0x101816545F6bd2b1076434B54383a1E633390A2E);
    
    setAddress("mainnet.axelarGateway", 0x4F4495243837681061C4743b74B3eEdf548D56A5);
    setAddress("mainnet.axelarGasService", 0x2d5d7d31F671F86C782533cc367F14109a082712);

    setAddress("mainnet.cctpTokenMessenger", 0xBd3fa81B58Ba92a82136038B25aDec7066af3155);

    setAddress("mainnet.squidRouter", 0xce16F69375520ab01377ce7B88f5BA8C48F8D666);

    setAddress("mainnet.deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);
    setAddress("polygon.deployer.create3", 0x6513Aedb4D1593BA12e50644401D976aebDc90d8);

    setAddress("polygon.usdc", 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    setAddress("polygon.stargateAdapter", 0xFF51a7C624Eb866917102707F3dA8bFb99Db8692);
    setAddress("polygon.lzEndpoint", 0x1a44076050125825900e736c501f859c50fE728c);
    setAddress("polygon.sushiXSwap", 0x804b526e5bF4349819fe2Db65349d0825870F8Ee);
    setAddress("polygon.axelarAdapter", 0xA62eC622DbA415Aa94110739B1f951B1202Cf322);
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