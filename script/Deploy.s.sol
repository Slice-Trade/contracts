// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import "../src/SliceCore.sol";
import {Constants} from "./Constants.sol";
import {IDeployer} from "./IDeployer.sol";
import "../src/Structs.sol";

contract SliceCoreDeployer is Script, Constants {
    uint256 immutable ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 immutable OP_SEPOLIA_CHAIN_ID = 11155420;
    uint256 immutable BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 immutable ARB_SEPOLIA_CHAIN_ID = 421614;
    uint256 immutable SCROLL_SEPOLIA_CHAIN_ID = 534351;

    uint256[] public deploymentChainIds;
    uint256[] public lzEndpointIds;

    bytes32 public salt;

    struct ConstructorArgs {
        address endpoint;
        address chainInfo;
        address sliceTokenDeployer;
        address owner;
    }

    Position[] public positions;

    function run() external {
        string memory mode = vm.envString("MODE");

        if (compareStrings(mode, "mainnet")) {
            deploymentChainIds.push(getUint("ARB_CHAIN_ID"));
            deploymentChainIds.push(getUint("OP_CHAIN_ID"));
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

        ConstructorArgs memory c = getConstructorArgs();

        bytes memory byteCode = abi.encodePacked(
            type(SliceCore).creationCode, abi.encode(c.endpoint, c.chainInfo, c.sliceTokenDeployer, c.owner)
        );

        uint256 deployerPrivKey = vm.envUint("KEY");

        vm.startBroadcast(deployerPrivKey);

        address sliceCoreAddress = create3Deployer.deploy(byteCode, salt);

        SliceCore(payable(sliceCoreAddress)).changeSliceTokenCreationEnabled(true);
        SliceCore(payable(sliceCoreAddress)).changeApprovedSliceTokenCreator(c.owner, true);
        SliceCore(payable(sliceCoreAddress)).changeApprovedSliceTokenCreator(address(this), true);

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

                SliceCore(payable(sliceCoreAddress)).setPeer(uint32(lzEndpointIds[i]), bytes32(uint256(uint160(sliceCoreAddress))));
            }
        } else {
            uint32 lzEid = uint32(getUint(masterChainId));
                console.log("Setting lz eid 2: ", lzEid);
            SliceCore(payable(sliceCoreAddress)).setPeer(lzEid, bytes32(uint256(uint160(sliceCoreAddress))));
        }

        vm.stopBroadcast();

        console.log("Slice Core deployed to: ");
        console.log(sliceCoreAddress);
    }

    function setSalt(string memory _saltString) internal {
        bytes32 result;
        assembly {
            result := mload(add(_saltString, 32))
        }
        salt = result;
    }

    function getConstructorArgs() internal view returns (ConstructorArgs memory) {
        if (block.chainid == getUint("ARB_CHAIN_ID")) {
            return ConstructorArgs(
                getAddress("arb.lzEndpoint"),
                getAddress("arb.chainInfo"),
                getAddress("arb.tokenDeployer"),
                getAddress("owner.mainnet")
            );
        } else if (block.chainid == getUint("OP_CHAIN_ID")) {
            return ConstructorArgs(
                getAddress("op.lzEndpoint"),
                getAddress("op.chainInfo"),
                getAddress("op.tokenDeployer"),
                getAddress("owner.mainnet")
            );
        } else if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("eth_sepolia.lzEndpoint"),
                getAddress("eth_sepolia.chainInfo"),
                getAddress("eth_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        } else if (block.chainid == OP_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("op_sepolia.lzEndpoint"),
                getAddress("op_sepolia.chainInfo"),
                getAddress("op_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        } else if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("base_sepolia.lzEndpoint"),
                getAddress("base_sepolia.chainInfo"),
                getAddress("base_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        } else if (block.chainid == ARB_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("arb_sepolia.lzEndpoint"),
                getAddress("arb_sepolia.chainInfo"),
                getAddress("arb_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        } else if (block.chainid == SCROLL_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("scroll_sepolia.lzEndpoint"),
                getAddress("scroll_sepolia.chainInfo"),
                getAddress("scroll_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        }
        revert("Unimplemented chain ID");
    }

    function setLzEids() internal {
        for (uint256 i = 0; i < deploymentChainIds.length; i++) {
            lzEndpointIds.push(getUint(deploymentChainIds[i]));
        }
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    function compareStrings(string memory str1, string memory str2) internal pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }

    function contains(uint256[] memory arr, uint256 el) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == el) {
                return true;
            }
        }
        return false;
    }
}
