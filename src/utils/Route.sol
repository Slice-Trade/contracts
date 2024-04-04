// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract Route {
    IUniswapV2Factory public immutable v2Factory;
    IUniswapV3Factory public immutable v3Factory;
    address public immutable rp;

    address public weth;

    address public sliceCore;

    constructor(address _v2Factory, address _v3Factory, address _rp, address _weth) {
        v2Factory = IUniswapV2Factory(_v2Factory);
        v3Factory = IUniswapV3Factory(_v3Factory);
        rp = _rp;
        weth = _weth;
    }

    function setSliceCore(address _sliceCore) external {
        sliceCore = _sliceCore;
    }

    function computeSingleRoute(bool rpHasToken, bool isV2, address tokenIn, address to, address pair)
        internal
        view
        returns (bytes memory route)
    {
        address token0;
        //address token1;
        uint8 direction;

        token0 = IUniswapV2Pair(pair).token0();
        //token1 = IUniswapV2Pair(pair).token1();

        if (token0 == tokenIn) {
            direction = uint8(0x01);
        } else {
            direction = uint8(0x00);
        }

        route = abi.encodePacked(
            uint8(rpHasToken ? 0x01 : 0x02), // 0x01 for pre-transfer to rp & 0x02 for transferFrom msg.sender
            tokenIn,
            uint8(0x01), // always does 1 route
            uint16(0xffff), // always does full amount
            uint8(isV2 ? 0x00 : 0x01), // poolType (0 = v2, 1 = v3)
            pair,
            direction,
            to
        );

        console.log(iToHex(route));
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

    function computeMultihopRoute(bool rpHasToken, bool isV2, address tokenIn, address to, address pair1, address pair2)
        internal
        view
        returns (bytes memory route)
    {
        address pair1token0 = IUniswapV2Pair(pair1).token0();
        //address pair1token1 = IUniswapV2Pair(pair1).token1();

        address pair2token0 = IUniswapV2Pair(pair2).token0();
        //address pair2token1 = IUniswapV2Pair(pair2).token1();

        uint8 direction1;
        uint8 direction2;

        if (pair1token0 == tokenIn) {
            direction1 = uint8(0x01);
        } else {
            direction1 = uint8(0x00);
        }

        if (pair2token0 == weth) {
            direction2 = uint8(0x01);
        } else {
            direction2 = uint8(0x00);
        }

        route = bytes.concat(
            abi.encodePacked(
                // first part: from usdc to weth
                uint8(rpHasToken ? 0x01 : 0x02), // 0x01 for pre-transfer to rp & 0x02 for transferFrom msg.sender
                tokenIn,
                uint8(0x01), // always does 1 route
                uint16(0xffff), // always does full amount
                uint8(isV2 ? 0x00 : 0x01), // poolType (0 = v2, 1 = v3)
                pair1,
                direction1,
                pair2
            ),
            abi.encodePacked(
                uint8(rpHasToken ? 0x01 : 0x02),
                weth,
                uint8(0x01),
                uint16(0xffff),
                uint8(isV2 ? 0x00 : 0x01),
                pair2,
                direction2,
                to
            ));

        console.log(iToHex(route));
    } 

    function computeRoute(bool rpHasToken, bool isV2, address tokenIn, address tokenOut, uint24 /* fee */, address to)
        public
        view
        returns (bytes memory route)
    {
        if (isV2) {
            address pair = v2Factory.getPair(tokenIn, tokenOut);
            // If pair is null need to do a multihop swap from usdc to weth to dst token
            if (pair != address(0) && tokenOut == weth) {
                route = computeSingleRoute(rpHasToken, isV2, tokenIn, to, pair);
            } else {
                address pair1 = v2Factory.getPair(tokenIn, weth);
                address pair2 = v2Factory.getPair(weth, tokenOut);
                route = computeMultihopRoute(rpHasToken, isV2, tokenIn, to, pair1, pair2);
            }
        } 
        else {
            // TODO
            //address pair = v3Factory.getPool(tokenIn, tokenOut, fee);
            //address token0 = IUniswapV3Pool(pair).token0();
            //address token1 = IUniswapV3Pool(pair).token1();
        }
    }
}
