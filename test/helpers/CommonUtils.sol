// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../helpers/Helper.sol";
import {ChainInfo} from "../../src/utils/ChainInfo.sol";
import {SliceTokenDeployer} from "../../src/utils/SliceTokenDeployer.sol";
import {SliceCore} from "../../src/SliceCore.sol";
import {IDeployer} from "../../script/IDeployer.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";
import {IWETH} from "../../src/external/IWETH.sol";
import {CrossChainVault} from "../../src/CrossChainVault/CrossChainVault.sol";
import {Chain as SliceChain, Position} from "../../src/Structs.sol";

contract CommonUtils is Helper {
    IERC20 public wbtc;
    IWETH public weth;
    IERC20 public link;

    uint256 public wbtcUnits = 100000000;
    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    enum ChainSelect {
        MAINNET,
        POLYGON,
        OPTIMISM
    }

    constructor() {
        wbtc = IERC20(getAddress("mainnet.wbtc"));
        weth = IWETH(getAddress("mainnet.weth"));
        link = IERC20(getAddress("mainnet.link"));
    }

    function deployTestContracts(ChainSelect chainSelect, string memory salt, Position[] storage positions)
        internal
        returns (address sliceCore, address tokenAddr, address sVault)
    {
        if (chainSelect == ChainSelect.MAINNET) {
            selectMainnet();
        } else if (chainSelect == ChainSelect.POLYGON) {
            selectPolygon();
        } else if (chainSelect == ChainSelect.OPTIMISM) {
            selectOptimism();
        }

        ChainInfo chainInfo = new ChainInfo();

        SliceTokenDeployer deployer = new SliceTokenDeployer();

        address endpoint = getAddress(
            chainSelect == ChainSelect.MAINNET
                ? "mainnet.layerZeroEndpoint"
                : (chainSelect == ChainSelect.POLYGON ? "polygon.layerZeroEndpoint" : "optimism.layerZeroEndpoint")
        );

        bytes memory byteCode = abi.encodePacked(
            type(SliceCore).creationCode, abi.encode(endpoint, address(chainInfo), address(deployer), dev)
        );

        IDeployer create3Deployer = IDeployer(
            getAddress(
                chainSelect == ChainSelect.MAINNET
                    ? "mainnet.deployer.create3"
                    : (chainSelect == ChainSelect.POLYGON ? "polygon.deployer.create3" : "optimism.deployer.create3")
            )
        );

        //address _deployedAddr = create3Deployer.deployedAddress(byteCode, dev, stringToBytes32("TEST"));
        if (stringToBytes32(salt) == bytes32(0)) {
            salt = "TEST";
        }
        sliceCore = create3Deployer.deploy(byteCode, stringToBytes32(salt));

        // enable slice token creation
        SliceCore(payable(sliceCore)).changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        SliceCore(payable(sliceCore)).changeApprovedSliceTokenCreator(dev, true);
        // set peer address
        IOAppCore(sliceCore).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : (chainSelect == ChainSelect.POLYGON ? 30101 : 30101)),
            bytes32(uint256(uint160(sliceCore)))
        );

        tokenAddr = SliceCore(payable(sliceCore)).createSlice("Slice Token", "SC", positions);

        bytes memory byteCodeVault = abi.encodePacked(
            type(CrossChainVault).creationCode, abi.encode(sliceCore, address(chainInfo), endpoint, dev)
        );

        sVault = create3Deployer.deploy(byteCodeVault, stringToBytes32("testvault"));

        IOAppCore(sVault).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : (chainSelect == ChainSelect.POLYGON ? 30101 : 30101)),
            bytes32(uint256(uint160(sVault)))
        );
    }

    function stringToBytes32(string memory _string) internal pure returns (bytes32 result) {
        require(bytes(_string).length <= 32, "String too long"); // Ensure string length is not greater than 32 bytes

        assembly {
            result := mload(add(_string, 32))
        }
    }

    function bytes32ToHexString(bytes32 _bytes32) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = hexChars[uint256(uint8(_bytes32[i] >> 4))];
            str[1 + i * 2] = hexChars[uint256(uint8(_bytes32[i] & 0x0f))];
        }
        return string(str);
    }

    function toUint128Array(uint256[] memory arr) internal pure returns (uint128[] memory) {
        uint128[] memory _arr = new uint128[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            _arr[i] = uint128(arr[i]);
        }
        return _arr;
    }

    function fillPositions(Position[] storage positions) internal {
        // create positions
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits
        );

        Position memory linkPosition = Position(
            1, // mainnet
            address(link), // chainlink
            18,
            linkUnits // 20 LINK
        );

        Position memory wbtcPosition = Position({chainId: 1, token: address(wbtc), decimals: 8, units: wbtcUnits});

        positions.push(wethPosition);
        positions.push(linkPosition);
        positions.push(wbtcPosition);
    }
}
