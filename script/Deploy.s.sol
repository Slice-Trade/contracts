// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import "../src/SliceCore.sol";

contract SliceCoreDeployer is Script {
    function run() external {
        bytes memory creationCode = type(SliceCore).creationCode;
        string memory bar = iToHex(creationCode);
        console.log(bar);
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