// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./InputStream.sol";

// TODO: on frontend/server change first command code to 01 and remove 000bb8 everywhere
library RouteVerifier {
    using InputStream for uint256;

    error FirstCommandCodeNot01(uint8 commandCode);
    error InvalidPoolType(uint8 poolType);
    error InvalidDirection(uint8 direction);
    error TokenOutReceiverNotSliceCore(address receiver);
    error InvalidShare();

    function verifyRoute(address core, bytes memory _route) internal pure {
        // create stream from route
        uint256 stream = InputStream.createStream(_route);
        uint16 _iterations = 0;

        while (stream.isNotEmpty()) {
            // read uint8 command code --> verify that it is 1 if this is the first iteration
            uint8 commandCode = stream.readUint8();
            if (_iterations == 0 && commandCode != 1) {
                revert FirstCommandCodeNot01(commandCode);
            }
            // if second iteration it can be 1 or 4
            if (commandCode == 4) {
                stream.readAddress();
                uint8 poolType = stream.readUint8();
                if (poolType > 2) revert InvalidPoolType(poolType); // Pool type must be 00, 01, or 02
                stream.readAddress();
                uint8 direction = stream.readUint8();
                if (direction > 1) revert InvalidDirection(direction); // Direction must be 00 or 01
                address to = stream.readAddress();
                if (!stream.isNotEmpty() && to != core)
                    revert TokenOutReceiverNotSliceCore(to); // Token out receiver must be SliceCore
            } else {
                // read address
                stream.readAddress();
                // read number of trades in swap
                uint8 numTrades = stream.readUint8();
            
                for (uint256 i = 0; i < numTrades; i++) {
                    // read the share
                    uint16 share = stream.readUint16();
                    if (share > type(uint16).max) revert InvalidShare();

                    // read the pool type
                    uint8 poolType = stream.readUint8();
                    // verify pool type
                    if (poolType > 2) revert InvalidPoolType(poolType); // Pool type must be 00, 01, or 02

                    // read pool, direction, to
                    stream.readAddress();
                    uint8 direction = stream.readUint8();
                    if (direction > 1) revert InvalidDirection(direction); // Direction must be 00 or 01

                    address to = stream.readAddress();
                    // verify that if stream is empty, than to is the slice core address
                    if (!stream.isNotEmpty() && to != core)
                        revert TokenOutReceiverNotSliceCore(to); // Token out receiver must be SliceCore
                }
            }
            _iterations++;
        }
    }
}