// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./SliceCore.sol";

contract SliceCoreDeployer {
    event SliceCoreDeployed(address indexed core);
    function deploySliceCore(bytes32 salt) external {
        address core = Create2.deploy(0, salt, type(SliceCore).creationCode);
        SliceCore(payable(core)).transferOwnership(msg.sender);
        emit SliceCoreDeployed(core);
    }
}

contract AddressChecker {
    function computeAddress(bytes32 salt) public view returns (address) {
        return Create2.computeAddress(salt, keccak256(abi.encodePacked(type(SliceCore).creationCode)));
    }

    function addressExists(address _address) internal view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_address)
        }
        return codeSize > 0;
    }
}