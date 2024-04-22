// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "./Constants.sol";

abstract contract Helper is Test, Constants {
    address payable dev;
    address payable[] users;

    constructor() {
        Users helper = new Users();
        users = helper.create(20);
        dev = users[0];
    }

    function advanceBlocks(uint256 delta) internal returns (uint256 blockNumber) {
        blockNumber = block.number + delta;
        vm.roll(blockNumber);
    }

    function advanceTime(uint256 delta) internal returns (uint256 timestamp) {
        timestamp = block.timestamp + delta;
        vm.warp(timestamp);
    }

    function forkMainnet() internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function forkMainnet(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
    }

    function forkOptimism(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("OPTIMISM_RPC_URL"), blockNumber);
    }

    function forkArbitrum(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"), blockNumber);
    }

    function forkPolygon(uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"), blockNumber);
    }

    function makePersistent(address contractAddress) internal {
        vm.makePersistent(contractAddress);
    }
}

contract Users is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function next() internal returns (address payable) {
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    function create(uint256 num) external returns (address payable[] memory) {
        address payable[] memory users = new address payable[](num);
        for (uint256 i = 0; i < num; i++) {
            address payable user = next();
            vm.deal(user, 100 ether);
            users[i] = user;
        }
        return users;
    }
}
