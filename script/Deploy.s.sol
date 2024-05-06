// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import "../src/SliceCore.sol";
import {Constants} from  "./Constants.sol";
import {IDeployer} from "./IDeployer.sol";
import "../src/Structs.sol";

contract SliceCoreDeployer is Script, Constants {
    uint immutable ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint immutable OP_SEPOLIA_CHAIN_ID = 11155420;

    bytes32 public salt;
    
    struct ConstructorArgs {
        address paymentToken;
        address sushiXSwap;
        address stargateAdapter;
        address axelarAdapter;
        address endpoint;
        address chainInfo;
        address sliceTokenDeployer;
        address owner;
    }

    Position[] public positions;

    function run() external {
        string memory _saltString = vm.envString("SALT");
        setSalt(_saltString);
        IDeployer create3Deployer = IDeployer(getAddress("deployer.create3"));

        ConstructorArgs memory c = getConstructorArgs();

        bytes memory byteCode = abi.encodePacked(
            type(SliceCore).creationCode,
            abi.encode(
                c.paymentToken,
                c.sushiXSwap,
                c.stargateAdapter,
                c.axelarAdapter,
                c.endpoint,
                c.chainInfo,
                c.sliceTokenDeployer,
                c.owner
            )
        );

        uint256 deployerPrivKey = vm.envUint("KEY");

        vm.startBroadcast(deployerPrivKey);

        address sliceCoreAddress = create3Deployer.deploy(
            byteCode,
            salt
        );

        SliceCore(payable(sliceCoreAddress)).changeSliceTokenCreationEnabled(true);
        SliceCore(payable(sliceCoreAddress)).changeApprovedSliceTokenCreator(c.owner, true);
        SliceCore(payable(sliceCoreAddress)).changeApprovedSliceTokenCreator(address(this), true);
        
        // TODO: get all chains and set peer to all of them
        /// @dev WARNING: only on testnets for now
        if (block.chainid == 11155111) {
            SliceCore(payable(sliceCoreAddress)).setPeer(40232, bytes32(uint256(uint160(sliceCoreAddress))));
        } else if (block.chainid == 11155420) {
            SliceCore(payable(sliceCoreAddress)).setPeer(40161, bytes32(uint256(uint160(sliceCoreAddress))));
            positions.push(Position(11155111,0xB36c4ef1e4Bc67e323581bDd7F48702d016Ebf19,2184000000000000000000));
            SliceCore(payable(sliceCoreAddress)).createSlice("TEST", "TT", positions);
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
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("eth_sepolia.paymentToken"),
                getAddress("eth_sepolia.sushiXSwap"),
                getAddress("eth_sepolia.stargateAdapter"),
                getAddress("eth_sepolia.axelarAdapter"),
                getAddress("eth_sepolia.lzEndpoint"),
                getAddress("eth_sepolia.chainInfo"),
                getAddress("eth_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        } else if (block.chainid == OP_SEPOLIA_CHAIN_ID) {
            return ConstructorArgs(
                getAddress("op_sepolia.paymentToken"),
                getAddress("op_sepolia.sushiXSwap"),
                getAddress("op_sepolia.stargateAdapter"),
                getAddress("op_sepolia.axelarAdapter"),
                getAddress("op_sepolia.lzEndpoint"),
                getAddress("op_sepolia.chainInfo"),
                getAddress("op_sepolia.tokenDeployer"),
                getAddress("owner")
            );
        }
        revert("Unimplemented chain ID");
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
}