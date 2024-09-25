// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import {Constants} from "./Constants.sol";
import {IDeployer} from "./IDeployer.sol";
import {DeployUtils} from "./DeployUtils.sol";
import {CrossChainVault} from "../src/CrossChainVault/CrossChainVault.sol";
import "../src/CrossChainVault/CrossChainVaultStructs.sol";

contract CrossChainVaultDeployer is Script, Constants, DeployUtils {
    uint256 immutable ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 immutable OP_SEPOLIA_CHAIN_ID = 11155420;
    uint256 immutable BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 immutable ARB_SEPOLIA_CHAIN_ID = 421614;
    uint256 immutable SCROLL_SEPOLIA_CHAIN_ID = 534351;

    uint256[] public deploymentChainIds;
    uint256[] public lzEndpointIds;

    bytes32 public salt;

    struct ConstructorArgs {
        address sliceCore;
        address chainInfo;
        address lzEndpointId;
        address owner;
    }

    function run() external {
        string memory mode = vm.envString("MODE");

        if (compareStrings(mode, "mainnet")) {
            deploymentChainIds.push(getUint("ARB_CHAIN_ID"));
            deploymentChainIds.push(getUint("OP_CHAIN_ID"));
            deploymentChainIds.push(getUint("BASE_CHAIN_ID"));
        } else {
            deploymentChainIds.push(getUint("ETH_SEPOLIA_CHAIN_ID"));
            deploymentChainIds.push(getUint("OP_SEPOLIA_CHAIN_ID"));
            deploymentChainIds.push(getUint("BASE_SEPOLIA_CHAIN_ID"));
            deploymentChainIds.push(getUint("ARB_SEPOLIA_CHAIN_ID"));
            deploymentChainIds.push(getUint("SCROLL_SEPOLIA_CHAIN_ID"));
        }

        setLzEids();

        string memory _saltString = vm.envString("SALT");
        setSalt(_saltString);
        IDeployer create3Deployer = IDeployer(getAddress("deployer.create3"));

        ConstructorArgs memory c /* = getConstructorArgs() */; // TODO

        bytes memory byteCode = abi.encodePacked(
            type(CrossChainVault).creationCode, abi.encode(c.sliceCore, c.chainInfo, c.lzEndpointId, c.owner)
        );

        uint256 deployerPrivKey = vm.envUint("KEY");

        vm.startBroadcast(deployerPrivKey);

        address crossChainVaultAddress = create3Deployer.deploy(byteCode, salt);

        // TODO: Do we need any other config here?
        
        uint256 masterChainId;

        if (compareStrings(mode, "mainnet")) {
            masterChainId = vm.envUint("MASTER_CHAIN_ID");
        } else {
            masterChainId = vm.envUint("MASTER_CHAIN_ID_TESTNET");
        }

        if (masterChainId == block.chainid) {
            for (uint256 i = 0; i < lzEndpointIds.length; i++) {
                uint256 masterLzEid = getUint(block.chainid);
                if (masterLzEid == lzEndpointIds[i]) {
                    continue;
                }
                console.log("Setting lz eid: ", lzEndpointIds[i]);

                CrossChainVault(payable(crossChainVaultAddress)).setPeer(uint32(lzEndpointIds[i]), bytes32(uint256(uint160(crossChainVaultAddress))));
            }
        } else {
            uint32 lzEid = uint32(getUint(masterChainId));
                console.log("Setting lz eid 2: ", lzEid);
            CrossChainVault(payable(crossChainVaultAddress)).setPeer(lzEid, bytes32(uint256(uint160(crossChainVaultAddress))));
        }

        vm.stopBroadcast();

        console.log("Cross chain vault deployed to: ");
        console.log(crossChainVaultAddress);
    }

    function setSalt(string memory _saltString) internal {
        bytes32 result;
        assembly {
            result := mload(add(_saltString, 32))
        }
        salt = result;
    }

     function setLzEids() internal {
        for (uint256 i = 0; i < deploymentChainIds.length; i++) {
            lzEndpointIds.push(getUint(deploymentChainIds[i]));
        }
    }
}
