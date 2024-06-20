// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/Structs.sol";

contract CrossChainPositionCreator {
    uint256 wmaticUnits = 95000000000000000000;

    Position public p1 = Position(137, address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), 18, wmaticUnits);
    Position public p2 = Position(137, address(0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39), 18, wmaticUnits);
    Position public p3 = Position(137, address(0x61299774020dA444Af134c82fa83E3810b309991), 18, wmaticUnits);
    Position public p4 = Position(137, address(0x6f7C932e7684666C9fd1d44527765433e01fF61d), 18, wmaticUnits);
    Position public p5 = Position(137, address(0x5fe2B58c013d7601147DcdD68C143A77499f5531), 18, wmaticUnits);
    Position public p6 = Position(137, address(0xe5B49820e5A1063F6F4DdF851327b5E8B2301048), 18, wmaticUnits);
    Position public p7 = Position(137, address(0xD6DF932A45C0f255f85145f286eA0b292B21C90B), 18, wmaticUnits);
    Position public p8 = Position(137, address(0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683), 18, wmaticUnits);
    Position public p9 = Position(137, address(0x41b3966B4FF7b427969ddf5da3627d6AEAE9a48E), 18, wmaticUnits);
    Position public p10 = Position(137, address(0xEe327F889d5947c1dc1934Bb208a1E792F953E96), 18, wmaticUnits);
    Position public p11 = Position(137, address(0x50B728D8D964fd00C2d0AAD81718b71311feF68a), 18, wmaticUnits);
    Position public p12 = Position(137, address(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4), 18, wmaticUnits);
    Position public p13 = Position(137, address(0xC3Ec80343D2bae2F8E680FDADDe7C17E71E114ea), 18, wmaticUnits);
    Position public p14 = Position(137, address(0xB7b31a6BC18e48888545CE79e83E06003bE70930), 18, wmaticUnits);
    Position public p15 = Position(137, address(0x9c2C5fd7b07E95EE044DDeba0E97a665F142394f), 18, wmaticUnits);
    Position public p16 = Position(137, address(0x282d8efCe846A88B159800bd4130ad77443Fa1A1), 18, wmaticUnits);
    Position public p17 = Position(137, address(0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c), 18, wmaticUnits);
    Position public p18 = Position(137, address(0xa1428174F516F527fafdD146b883bB4428682737), 18, wmaticUnits);
    Position public p19 = Position(137, address(0x101A023270368c0D50BFfb62780F4aFd4ea79C35), 18, wmaticUnits);
    Position public p20 = Position(137, address(0x3Cef98bb43d732E2F285eE605a8158cDE967D219), 18, wmaticUnits);

    Position[] private ccPositions;

    constructor() {
        ccPositions.push(p1);
        ccPositions.push(p2);
        ccPositions.push(p3);
        ccPositions.push(p4);
        ccPositions.push(p5);
        ccPositions.push(p6);
        ccPositions.push(p7);
        ccPositions.push(p8);
        ccPositions.push(p9);
        ccPositions.push(p10);
        ccPositions.push(p11);
        ccPositions.push(p12);
        ccPositions.push(p13);
        ccPositions.push(p14);
        ccPositions.push(p15);
        ccPositions.push(p16);
        ccPositions.push(p17);
        ccPositions.push(p18);
        ccPositions.push(p19);
        ccPositions.push(p20);
    }

    function getCCPositions(uint8 length) external view returns (Position[] memory) {
        if (length < 1 || length > 20) {
            revert("Length must be between 1 and 20");
        }

        Position[] memory positions = new Position[](length);
        for (uint256 i = 0; i < length; i++) {
            positions[i] = ccPositions[i];
        }

        return positions;
    }
}
