// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILayerZeroEndpointV2, MessagingParams} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/ChainInfo.sol";

import "../src/interfaces/ISliceCoreErrors.sol";
import "../src/SliceCore.sol";
import "../src/SliceToken.sol";
import {Chain as SliceChain} from "../src/Structs.sol";
import "../src/utils/SliceTokenDeployer.sol";

import {IDeployer} from "../script/IDeployer.sol";

import {TokenMock} from "./mocks/TokenMock.sol";

import {LZFeeEstimator} from "./helpers/LZFeeEstimator.sol";
import {CrossChainPositionCreator} from "./helpers/CrossChainPositionCreator.sol";

// TODO: write a test that makes sures mint / redeem / refund fails if the fees length is incorrect

contract SliceCoreTest is Helper {
    using TokenAmountUtils for SliceCoreTest;

    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720
    uint256 immutable OPTIMISM_BLOCK_NUMBER = 117930462; //TSTAMP: 1711459720
    SliceCore core;
    SliceToken token;

    SliceToken ccToken;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public link;
    IERC20 public wbtc;

    IERC20 public wmaticPolygon;

    Position[] public positions;

    uint256 maxEstWethPrice = 40000000000; // 40000 usdc
    uint256 maxEstLinkPrice = 45000000000; // 45000 usdc

    uint256 constant MAX_ESTIMATED_PRICE = 160000000000; // 160000 USDC

    uint256[] public maxEstimatedPrices;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK
    uint256 public wbtcUnits = 100000000;

    uint256[] public wrongPrices;

    /* CROSS_CHAIN */
    uint256 maxWMaticPrice = 100000000; //100usdc
    uint256 wmaticUnits = 95000000000000000000; // 95matic

    uint256[] public maxEstCCPrices;
    Position[] public ccPositions;

    CrossChainPositionCreator public ccPosCreator;

    int8 public failAtIdx = -1;

    enum ChainSelect {
        MAINNET,
        POLYGON,
        OPTIMISM
    }

    address polygonLink = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;

    function deployTestContracts(ChainSelect chainSelect, string memory salt)
        internal
        returns (address sliceCore, address tokenAddr)
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
        ISliceCore(sliceCore).changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        ISliceCore(sliceCore).changeApprovedSliceTokenCreator(dev, true);
        // set peer address
        IOAppCore(sliceCore).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : (chainSelect == ChainSelect.POLYGON ? 30101 : 30101)),
            bytes32(uint256(uint160(sliceCore)))
        );

        tokenAddr = ISliceCore(sliceCore).createSlice("Slice Token", "SC", positions);
    }

    function stringToBytes32(string memory _string) internal pure returns (bytes32 result) {
        require(bytes(_string).length <= 32, "String too long"); // Ensure string length is not greater than 32 bytes

        assembly {
            result := mload(add(_string, 32))
        }
    }

    function isContract(address contractAddress) internal view returns (bool) {
        bytes32 existingCodeHash = contractAddress.codehash;

        // https://eips.ethereum.org/EIPS/eip-1052
        // keccak256('') == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
        return existingCodeHash != bytes32(0)
            && existingCodeHash != 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    }

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */

    function setUp() public {
        forkMainnet(MAINNET_BLOCK_NUMBER);
        forkPolygon(POLYGON_BLOCK_NUMBER);
        selectMainnet();

        usdc = IERC20(getAddress("mainnet.usdc"));
        link = IERC20(getAddress("mainnet.link"));
        weth = IWETH(getAddress("mainnet.weth"));
        wbtc = IERC20(getAddress("mainnet.wbtc"));

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        maxEstimatedPrices.push(maxEstWethPrice);
        maxEstimatedPrices.push(maxEstLinkPrice);

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);
        vm.startPrank(dev);

        // create positions
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits // 0.1 wETH
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

        (address sCore, address sToken) = deployTestContracts(ChainSelect.MAINNET, "");
        core = SliceCore(payable(sCore));
        token = SliceToken(payable(sToken));

        usdc.approve(address(core), MAX_ESTIMATED_PRICE * 10);
        usdc.approve(address(token), MAX_ESTIMATED_PRICE * 10);

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);

        ccPositions.push(ccPos);

        maxEstCCPrices.push(maxWMaticPrice);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        ccPosCreator = new CrossChainPositionCreator();

        vm.stopPrank();
    }

    function test_LZFeeEstimator() public {
        vm.startPrank(dev);
        Position memory ccPos2 = Position(56, address(wmaticPolygon), 18, wmaticUnits);
        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);

        ccPositions[0] = ccPos2;
        ccPositions.push(ccPos2);

        ccPositions.push(ccPos);
        ccPositions.push(ccPos);

        core.setPeer(30102, bytes32(uint256(uint160(address(core)))));

        address ccTokenAddr2 = core.createSlice("CC Slice", "CC", ccPositions);

        LZFeeEstimator feeEstimator =
            new LZFeeEstimator(core, core.chainInfo(), ILayerZeroEndpointV2(getAddress("polygon.layerZeroEndpoint")));
        uint128[] memory testingg = new uint128[](2);
        testingg[0] = 2000000000000000;
        testingg[1] = 1000000000000000;

        uint256[] memory fees = feeEstimator.estimateLzFee(ccTokenAddr2, CrossChainSignalType.MINT, testingg);
        uint256 feeTotal;
        for (uint256 i = 0; i < fees.length; i++) {
            feeTotal += fees[i];
        }

        vm.stopPrank();
    }

    function test_Cannot_LzReceive_NotEnoughMsgValue() public {
        CrossChainSignal memory ccs = CrossChainSignal({
            id: bytes32(0),
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REDEEM,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits,
            value: 1 ether
        });

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        vm.expectRevert("Not enough msg value provided");
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));
    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function test_CreateSlice() public {
        vm.startPrank(dev);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(users[1], true);

        // call create Slice token from that address
        vm.stopPrank();

        vm.prank(users[1]);

        address sliceTokenAddress = core.createSlice("Test Token", "TT", positions);
        // verify that the Slice token is deployed
        SliceToken deployedSliceToken = SliceToken(sliceTokenAddress);
        assertEq("Test Token", deployedSliceToken.name());
        assertEq("TT", deployedSliceToken.symbol());

        // verify that Slice token works
        Position[] memory slicePositions = deployedSliceToken.getPositions();
        for (uint256 i = 0; i < slicePositions.length; i++) {
            assertEq(positions[i].chainId, slicePositions[i].chainId);
            assertEq(positions[i].token, slicePositions[i].token);
            assertEq(positions[i].units, slicePositions[i].units);
        }

        // verify that Slice token address is registered in the core contract
        bool isSliceRegistered = core.isSliceTokenRegistered(sliceTokenAddress);
        assertEq(true, isSliceRegistered);
    }

    function test_Cannot_CreateSlice_NotAuthorized() public {
        vm.prank(dev);
        core.changeSliceTokenCreationEnabled(true);

        // call create Slice token from an unverified address
        vm.prank(users[2]);
        // verify that transaction fails with the correct revert message
        vm.expectRevert(bytes4(keccak256("UnauthorizedCaller()")));
        core.createSlice("Test Token", "TT", positions);
    }

    function test_Cannot_CreateSlice_CreationNotEnabled() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(false);

        vm.expectRevert(bytes4(keccak256("TokenCreationDisabled()")));
        core.createSlice("Test Token", "TT", positions);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ===============   collectUnderlying   ================    */
    /* =========================================================== */
    function test_CollectUnderlying() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsCollected(address(token), 1 ether, dev);
        uint128[] memory fees;
        token.mint(1 ether, fees);

        uint256 wethBalance = weth.balanceOf(dev);
        uint256 linkBalance = link.balanceOf(dev);
        uint256 wbtcBalance = wbtc.balanceOf(dev);
        assertEq(0, wethBalance);
        assertEq(0, linkBalance);
        assertEq(0, wbtcBalance);

        uint256 coreWethBalance = weth.balanceOf(address(core));
        uint256 coreLinkBalance = link.balanceOf(address(core));
        uint256 coreWbtcBalance = wbtc.balanceOf(address(core));
        assertEq(wethUnits, coreWethBalance);
        assertEq(linkUnits, coreLinkBalance);
        assertEq(wbtcUnits, coreWbtcBalance);

        uint256 tokenBalance = token.balanceOf(dev);
        assertEq(1 ether, tokenBalance);

        vm.stopPrank();
    }

    function test_CollectUnderlying_Fuzz(uint256 sliceTokenAmount) public {
        vm.assume(sliceTokenAmount < 1000 ether);

        uint256 minBtcUnits = TokenAmountUtils.getMinimumAmountInSliceToken(8);
        vm.assume(sliceTokenAmount > minBtcUnits);

        wethUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wethUnits, 18);
        linkUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, linkUnits, 18);
        wbtcUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wbtcUnits, 8);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsCollected(address(token), sliceTokenAmount, dev);
        uint128[] memory fees;
        token.mint(sliceTokenAmount, fees);

        uint256 wethBalance = weth.balanceOf(dev);
        uint256 linkBalance = link.balanceOf(dev);
        uint256 wbtcBalance = wbtc.balanceOf(dev);
        assertEq(0, wethBalance);
        assertEq(0, linkBalance);
        assertEq(0, wbtcBalance);

        uint256 coreWethBalance = weth.balanceOf(address(core));
        uint256 coreLinkBalance = link.balanceOf(address(core));
        uint256 coreWbtcBalance = wbtc.balanceOf(address(core));
        assertEq(wethUnits, coreWethBalance);
        assertEq(linkUnits, coreLinkBalance);
        assertEq(wbtcUnits, coreWbtcBalance);

        uint256 tokenBalance = token.balanceOf(dev);
        assertEq(sliceTokenAmount, tokenBalance);

        vm.stopPrank();
    }

    function test_CollectUnderlying_CrossChain() public {
        (bytes32 mintId,) = _mintCrossChain(20);
        assertNotEq(bytes32(0), mintId);

        uint256 tokenBalance = ccToken.balanceOf(dev);
        assertEq(1 ether, tokenBalance);
    }

    function test_CollectUnderlying_CrossChain_Fuzz(uint256 sliceTokenAmount, uint8 positionsLength) public {
        vm.assume(sliceTokenAmount < 10000 ether);
        vm.assume(positionsLength >= 1);
        vm.assume(positionsLength <= 20);

        uint256 minBtcUnits = TokenAmountUtils.getMinimumAmountInSliceToken(8);
        vm.assume(sliceTokenAmount > minBtcUnits);

        (bytes32 mintId,) = _mintCrossChainFuzz(sliceTokenAmount, positionsLength);

        assertNotEq(bytes32(0), mintId);

        uint256 tokenBalance = ccToken.balanceOf(dev);
        assertEq(sliceTokenAmount, tokenBalance);
    }

    function test_CollectUnderlying_HighDecimals() public {
        vm.startPrank(dev);
        TokenMock tokenMock = new TokenMock("Test", "T");
        uint256 mockTokenUnits = 10 ** 24;

        tokenMock.mint(mockTokenUnits);

        Position memory _pos =
            Position({chainId: 1, token: address(tokenMock), decimals: tokenMock.decimals(), units: mockTokenUnits});
        positions.push(_pos);

        address sliceTokenAddress = core.createSlice("Test Token", "TT", positions);
        // verify that the Slice token is deployed
        SliceToken deployedSliceToken = SliceToken(sliceTokenAddress);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);
        deal(address(tokenMock), address(dev), mockTokenUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);
        tokenMock.approve(address(core), mockTokenUnits);
        uint128[] memory fees;
        deployedSliceToken.mint(1 ether, fees);

        uint256 mockTokenBalance = tokenMock.balanceOf(dev);
        assertEq(0, mockTokenBalance);
        uint256 coreMockTokenBalance = tokenMock.balanceOf(address(core));
        assertEq(mockTokenUnits, coreMockTokenBalance);
    }

    function test_Cannot_CollectUnderlying_NotRegisteredSliceToken() public {
        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        core.collectUnderlying(bytes32(0), fees);
    }

    function test_Cannot_CollectUnderlying_InvalidMintId() public {
        vm.prank(address(token));

        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        core.collectUnderlying(bytes32(0), fees);
    }

    function test_Cannot_CollectUnderlying_LocalAssetTransferFailed_NoFunds() public {
        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);
        uint128[] memory fees;
        vm.expectRevert();
        token.mint(1 ether, fees);

        vm.stopPrank();
    }

    function test_Cannot_CollectUnderlying_LocalAssetTransferFailed_NotApproved() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(weth), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);
        uint128[] memory fees;

        vm.expectRevert();

        token.mint(1 ether, fees);
    }

    function test_Cannot_CollectUnderlying_NoLzPeer() public {
        vm.startPrank(dev);

        Position memory ccPos2 = Position(56, address(wmaticPolygon), 18, wmaticUnits);
        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);

        ccPositions[0] = ccPos2;
        ccPositions.push(ccPos2);

        ccPositions.push(ccPos);
        ccPositions.push(ccPos);

        deal(address(core), 10 ether);
        uint128[] memory fees = new uint128[](2);
        fees[0] = 1 ether;
        fees[1] = 1 ether;
        address ccTokenAddr2 = core.createSlice("CC Slice", "CC", ccPositions);
        vm.expectRevert();
        SliceToken(ccTokenAddr2).mint(1 ether, fees);
    }

    function test_CrossChainMessaging() public {
        vm.startPrank(dev);

        Position memory ccPos2 = Position(56, address(wmaticPolygon), 18, wmaticUnits);
        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);

        ccPositions[0] = ccPos2;
        ccPositions.push(ccPos2);

        ccPositions.push(ccPos);
        ccPositions.push(ccPos);

        core.setPeer(30102, bytes32(uint256(uint160(address(core)))));

        deal(dev, 100 ether);

        address ccTokenAddr2 = core.createSlice("CC Slice", "CC", ccPositions);

        uint128[] memory fees = new uint128[](2);
        fees[0] = 100;
        fees[1] = 100;

        vm.recordLogs();
        SliceToken(ccTokenAddr2).mint{value: 10 ether}(1 ether, fees);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; i++) {
            if (i == 2) {
                (bytes memory encodedPayload,,) = abi.decode(entries[i].data, (bytes, bytes, address));
                Packet memory packet = decodePacket(encodedPayload);

                SliceChain memory _chain = IChainInfo(address(core.chainInfo())).getChainInfo(56);

                assertEq(_chain.lzEndpointId, packet.dstEid);

                CrossChainSignal[] memory signals = abi.decode(packet.message, (CrossChainSignal[]));
                for (uint256 j = 0; j < signals.length; j++) {
                    assertEq(signals[j].srcChainId, 1);
                    assertEq(signals[j].underlying, address(wmaticPolygon));
                    assertEq(signals[j].units, wmaticUnits);
                }
            } else if (i == 5) {
                (bytes memory encodedPayload,,) = abi.decode(entries[i].data, (bytes, bytes, address));
                Packet memory packet = decodePacket(encodedPayload);

                SliceChain memory _chain = IChainInfo(address(core.chainInfo())).getChainInfo(137);

                assertEq(_chain.lzEndpointId, packet.dstEid);

                CrossChainSignal[] memory signals = abi.decode(packet.message, (CrossChainSignal[]));
                for (uint256 j = 0; j < signals.length; j++) {
                    assertEq(signals[j].srcChainId, 1);
                    assertEq(signals[j].underlying, address(wmaticPolygon));
                    assertEq(signals[j].units, wmaticUnits);
                }
            }
        }
        vm.stopPrank();
    }

    /// @dev this test ensures that the message grouping loop does not break if there is a list of local positions in the middle of the positions array
    function test_CrossChainMessaging_LocalPositionsInTheMiddle() public {
        vm.startPrank(dev);
        forkOptimism(OPTIMISM_BLOCK_NUMBER);
        address linkOp = 0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6;
        Position memory ccPos2 = Position(10, linkOp, 18, wmaticUnits);
        Position memory ccPos3 = Position(56, address(wmaticPolygon), 18, wmaticUnits);

        positions.push(ccPos2);
        positions.push(ccPos3);

        (address sliceCore, address sliceToken) = deployTestContracts(ChainSelect.OPTIMISM, "");

        deal(dev, 100 ether);
        deal(linkOp, dev, wmaticUnits);
        IERC20(linkOp).approve(sliceCore, wmaticUnits);

        core = SliceCore(payable(sliceCore));
        token = SliceToken(sliceToken);

        core.setPeer(30102, bytes32(uint256(uint160(address(core)))));

        uint128[] memory fees = new uint128[](2);
        fees[0] = 100;
        fees[1] = 100;

        vm.recordLogs();
        token.mint{value: 10 ether}(1 ether, fees);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (i == 4) {
                (bytes memory encodedPayload,,) = abi.decode(entries[i].data, (bytes, bytes, address));
                Packet memory packet = decodePacket(encodedPayload);
                console.log(packet.dstEid);
                assertEq(packet.dstEid, 30101);
            } else if (i == 7) {
                (bytes memory encodedPayload,,) = abi.decode(entries[i].data, (bytes, bytes, address));
                Packet memory packet = decodePacket(encodedPayload);
                console.log(packet.dstEid);
                assertEq(packet.dstEid, 30102);
            }
        }
    }

    function test_MintComplete(uint8 length) public {
        vm.assume(length >= 1);
        vm.assume(length <= 20);
        Position[] memory _positions = ccPosCreator.getCCPositions(length);

        for (uint256 i = 1; i < _positions.length; i++) {
            ccPositions.push(_positions[i]);
        }
        vm.startPrank(dev);

        address ccTokenManyPos = core.createSlice("CCSlice", "CCS", ccPositions);
        ccToken = SliceToken(ccTokenManyPos);

        (address pCore, uint256 feeTotal,, uint256[] memory feesForMsgs) =
            _estimateFee(address(0), CrossChainSignalType.MINT, CrossChainSignalType.MINT_COMPLETE);
        address polygonCore = pCore;

        bytes32 mintId = ccToken.mint{value: feeTotal}(1 ether, toUint128Array(feesForMsgs));

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            {
                CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
                    id: mintId,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.MINT_COMPLETE,
                    success: failAtIdx != int8(int256(i)),
                    user: dev,
                    underlying: ccPositions[i].token,
                    units: wmaticUnits,
                    value: 0
                });

                ccsMsgs[i] = _ccsResponse2;
            }
        }

        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        if (failAtIdx == -1) {
            vm.expectEmit(true, true, true, false);
            emit ISliceCore.UnderlyingAssetsCollected(address(ccToken), 1 ether, dev);
        }
        vm.stopPrank();
        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(_createOriginResp(polygonCore), bytes32(0), ccsEncoded2, dev, bytes(""));
    }

    /* =========================================================== */
    /*   ==============    redeemUnderlying    ================    */
    /* =========================================================== */
    function test_RedeemUnderlying() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);
        uint128[] memory fees;
        token.mint(1 ether, fees);
        uint256 wethTokenbalanceBefore = weth.balanceOf(address(core));
        uint256 linkTokenbalanceBefore = link.balanceOf(address(core));
        uint256 wbtcTokenbalanceBefore = wbtc.balanceOf(address(core));
        // call redeem underlying
        token.redeem(1 ether, fees);

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 linkBalance = link.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(linkBalance, positions[1].units);
        assertEq(wbtcBalance, positions[2].units);

        uint256 wethTokenbalance = weth.balanceOf(address(core));
        uint256 linkTokenbalance = link.balanceOf(address(core));
        uint256 wbtcTokenbalance = wbtc.balanceOf(address(core));

        assertEq(wethTokenbalanceBefore - wethTokenbalance, wethUnits);
        assertEq(linkTokenbalanceBefore - linkTokenbalance, linkUnits);
        assertEq(wbtcTokenbalanceBefore - wbtcTokenbalance, wbtcUnits);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function test_RedeemUnderlying_Fuzz(uint256 sliceTokenAmount) public {
        vm.assume(sliceTokenAmount < 1000 ether);

        uint256 minBtcUnits = TokenAmountUtils.getMinimumAmountInSliceToken(8);
        vm.assume(sliceTokenAmount > minBtcUnits);

        wethUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wethUnits, 18);
        linkUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, linkUnits, 18);
        wbtcUnits = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wbtcUnits, 8);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);
        uint128[] memory fees;
        token.mint(sliceTokenAmount, fees);

        uint256 wethTokenbalanceBefore = weth.balanceOf(address(core));
        uint256 linkTokenbalanceBefore = link.balanceOf(address(core));
        uint256 wbtcTokenbalanceBefore = wbtc.balanceOf(address(core));
        // call redeem underlying
        token.redeem(sliceTokenAmount, fees);

        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 linkBalance = link.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        assertEq(wethBalance, wethUnits);
        assertEq(linkBalance, linkUnits);
        assertEq(wbtcBalance, wbtcUnits);

        uint256 wethTokenbalance = weth.balanceOf(address(core));
        uint256 linkTokenbalance = link.balanceOf(address(core));
        uint256 wbtcTokenbalance = wbtc.balanceOf(address(core));

        assertEq(wethTokenbalanceBefore - wethTokenbalance, wethUnits);
        assertEq(linkTokenbalanceBefore - linkTokenbalance, linkUnits);
        assertEq(wbtcTokenbalanceBefore - wbtcTokenbalance, wbtcUnits);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function test_RedeemUnderlying_CrossChain_Fuzz(uint256 sliceTokenAmount, uint8 positionsLength) public {
        vm.assume(sliceTokenAmount > 0);
        vm.assume(sliceTokenAmount < 1000 ether);
        vm.assume(positionsLength >= 1);
        vm.assume(positionsLength <= 20);

        (bytes32 mintId, address polygonCore) = _mintCrossChainFuzz(sliceTokenAmount, positionsLength);
        assertNotEq(bytes32(0), mintId);
        vm.startPrank(dev);

        (, uint256 feeTotal, uint128[] memory fees, uint256[] memory feesForMsgs) =
            _estimateFee(polygonCore, CrossChainSignalType.REDEEM, CrossChainSignalType.REDEEM_COMPLETE);

        bytes32 redeemId = ccToken.redeem{value: feeTotal}(sliceTokenAmount, toUint128Array(feesForMsgs));
        assertNotEq(bytes32(0), redeemId);

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: redeemId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REDEEM,
                success: false,
                user: dev,
                underlying: ccPositions[i].token,
                units: TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18),
                value: uint256(fees[0])
            });
            ccsMsgs[i] = ccs;
        }

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});
        makePersistent(address(ccToken));
        // change network
        selectPolygon();
        deal(getAddress("polygon.layerZeroEndpoint"), uint256(fees[0]));
        vm.stopPrank();
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive{value: uint256(fees[0])}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            assertEq(
                TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18),
                IERC20(ccPositions[i].token).balanceOf(dev)
            );
            CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
                id: redeemId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REDEEM_COMPLETE,
                success: true,
                user: dev,
                underlying: ccPositions[i].token,
                units: TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18),
                value: 0
            });
            ccsMsgs[i] = _ccsResponse2;
        }

        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();
        vm.expectEmit(true, true, true, false);
        emit ISliceCore.UnderlyingAssetsRedeemed(address(ccToken), sliceTokenAmount, dev);

        deal(getAddress("mainnet.layerZeroEndpoint"), 0.1 ether);
        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive{value: 0.1 ether}(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        uint256 sliceTokenBalance = ccToken.balanceOf(dev);
        assertEq(0, sliceTokenBalance);
    }

    function test_Cannot_RedeemUnderlying_NotAuthorized() public {
        uint128[] memory fees;
        // verify that it reverts with the correct reason
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        // call redeem from not registered slice token
        core.redeemUnderlying(bytes32(0), fees);
    }

    function test_Cannot_RedeemUnderlying_RedeemIdDoesNotExist() public {
        uint128[] memory fees;
        vm.prank(address(ccToken));
        vm.expectRevert(bytes4(keccak256("RedeemIdDoesNotExist()")));
        core.redeemUnderlying(bytes32(""), fees);
    }

    function test_Cannot_RedeemUnderlying_LocalTransferFailed() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        uint128[] memory fees;
        token.mint(1 ether, fees);

        deal(address(weth), address(core), 0);
        deal(address(link), address(core), 0);
        deal(address(wbtc), address(core), 0);
        vm.expectRevert();
        token.redeem(1 ether, fees);
    }

    /* =========================================================== */
    /*   ====================    refund    ====================    */
    /* =========================================================== */
    function test_Refund() public {
        // transfer one of the assets to a new account
        deal(address(weth), address(dev), wethUnits);

        // make sure the balance of the other asset is 0
        uint256 balance = link.balanceOf(dev);
        assertEq(balance, 0);
        // approve that 1 asset
        vm.startPrank(dev);
        weth.approve(address(core), wethUnits);
        uint128[] memory fees;
        // make sure that the whole process fails with the correct error
        vm.expectRevert();
        // make sure that all balances are unchanged
        token.mint(1 ether, fees);
    }

    function test_Refund_CrossChain_refundLocal() public {
        bytes32 mintId = _prepareCrossChainRefund();

        address polygonCore = _doFailedMintOnPolygon(mintId);

        // send the response msg
        // create cross chain signal
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT_COMPLETE,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits,
            value: 0
        });
        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = _ccsResponse2;
        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        // expect the mint failed call to slice token here and event emit
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMintFailed(dev, 1 ether);

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        // make sure that the refund process is set in place
        (, uint256 signalsOk, uint256 signalsFailed,,) = SliceCore(core).transactionCompleteSignals(mintId);

        assertEq(signalsFailed, 1);
        assertEq(signalsOk, 1);

        uint256 wethBalanceBefore = weth.balanceOf(dev);
        assertEq(wethBalanceBefore, 0);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintId);
        bool isStateFailed = txInfo.state == TransactionState.FAILED;
        assertEq(isStateFailed, true);

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.RefundCompleted(dev, 1 ether);
        // do the refund calls
        (, uint256 totalFees,, uint256[] memory feesForMsgs) =
            _estimateFee(polygonCore, CrossChainSignalType.REFUND, CrossChainSignalType.REFUND_COMPLETE);

        ccToken.refund{value: totalFees}(mintId, toUint128Array(feesForMsgs));

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo2 = ccToken.getMint(mintId);
        bool isStateRefunded = txInfo2.state == TransactionState.REFUNDED;
        assertEq(isStateRefunded, true);

        uint256 wethBalanceAfter = weth.balanceOf(dev);
        assertEq(wethBalanceAfter, 1 ether);
    }

    function test_Refund_CrossChain_refundRemote(uint256 sliceTokenAmount, uint8 positionsLength, int8 _failAtIdx)
        public
    {
        vm.assume(sliceTokenAmount < 10000 ether);
        vm.assume(sliceTokenAmount > 0);
        vm.assume(positionsLength >= 2);
        vm.assume(positionsLength <= 20);

        vm.assume(_failAtIdx >= 0);
        vm.assume(_failAtIdx < int8(positionsLength));
        failAtIdx = _failAtIdx;

        (bytes32 mintId, address polygonCore) = _mintCrossChainFuzz(sliceTokenAmount, positionsLength);

        // make sure that the refund process is set in place
        (, uint256 signalsOk, uint256 signalsFailed,,) = SliceCore(core).transactionCompleteSignals(mintId);

        assertEq(signalsFailed, 1);
        assertEq(signalsOk, positionsLength - 1);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintId);
        bool isStateFailed = txInfo.state == TransactionState.FAILED;
        assertEq(isStateFailed, true);

        _handleMainnetResponseOnFailedMint(mintId, polygonCore, sliceTokenAmount, positionsLength);

        SliceTransactionInfo memory txInfo3 = ccToken.getMint(mintId);
        bool isStateRefunded = txInfo3.state == TransactionState.REFUNDED;
        assertEq(isStateRefunded, true);
    }

    function test_Cannot_Refund_NotSliceToken() public {
        // make sure that refund can only be called by slice token
        SliceTransactionInfo memory _txInfo;
        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        core.refund(_txInfo, fees);
    }

    function test_Cannot_Refund_InvalidState() public {
        // make sure that refund can only be called if state is refunding
        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));

        SliceTransactionInfo memory _txInfo =
            SliceTransactionInfo({id: bytes32(0), quantity: 1 ether, user: dev, state: TransactionState.OPEN});
        uint128[] memory fees;
        vm.prank(address(token));
        core.refund(_txInfo, fees);
    }

    function test_Cannot_Refund_NotAllCrossChainSignalsReceived() public {
        // do the cross chain testing logic but do not send 1 of the signals
        bytes32 mintId = _prepareCrossChainRefund();
        _doFailedMintOnPolygon(mintId);

        selectMainnet();
        uint128[] memory fees;

        vm.prank(address(core));
        ccToken.mintFailed(mintId);

        // make sure it fails with the correct error
        vm.expectRevert(bytes4(keccak256("NotAllCrossChainSignalsReceived()")));
        ccToken.refund(mintId, fees);
    }

    /* =========================================================== */
    /*  =========   changeSliceTokenCreationEnabled   ===========  */
    /* =========================================================== */
    function test_ChangeSliceTokenCreationEnabled() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);

        // verify that we can create slice tokens
        address newSliceToken = core.createSlice("New Test Token", "NTT", positions);
        bool isRegistered = core.isSliceTokenRegistered(newSliceToken);
        assertTrue(isRegistered);

        Position[] memory newTokenPositions = SliceToken(newSliceToken).getPositions();
        for (uint256 i = 0; i < newTokenPositions.length; i++) {
            assertEq(positions[i].chainId, newTokenPositions[i].chainId);
            assertEq(positions[i].token, newTokenPositions[i].token);
            assertEq(positions[i].units, newTokenPositions[i].units);
        }

        // disable slice token creation
        core.changeSliceTokenCreationEnabled(false);

        vm.expectRevert(bytes4(keccak256("TokenCreationDisabled()")));
        // verify that we cannot create slice tokens
        core.createSlice("New Test Token", "NTT", positions);
        vm.stopPrank();
    }

    function test_Cannot_ChangeSliceTokenCreationEnabled_NotAuthorized() public {
        vm.prank(users[2]);
        // verify that it reverts
        vm.expectRevert();
        // try changing enable/disable with non-owner address
        core.changeSliceTokenCreationEnabled(false);
    }

    /* =========================================================== */
    /*  ===============    set layer zero gas   =================  */
    /* =========================================================== */
    function test_SetLzBaseGas() public {
        vm.startPrank(dev);
        core.setLzBaseGas(CrossChainSignalType.MINT, 888888);
        uint256 gas = core.lzGasLookup(CrossChainSignalType.MINT);
        assertEq(gas, 888888);

        core.setLzBaseGas(CrossChainSignalType.MINT_COMPLETE, 888888);
        gas = core.lzGasLookup(CrossChainSignalType.MINT_COMPLETE);
        assertEq(gas, 888888);

        core.setLzBaseGas(CrossChainSignalType.REDEEM, 888888);
        gas = core.lzGasLookup(CrossChainSignalType.REDEEM);
        assertEq(gas, 888888);

        core.setLzBaseGas(CrossChainSignalType.REDEEM_COMPLETE, 888888);
        gas = core.lzGasLookup(CrossChainSignalType.REDEEM_COMPLETE);
        assertEq(gas, 888888);

        core.setLzBaseGas(CrossChainSignalType.REFUND, 888888);
        gas = core.lzGasLookup(CrossChainSignalType.REFUND);
        assertEq(gas, 888888);

        core.setLzBaseGas(CrossChainSignalType.REFUND_COMPLETE, 888888);
        gas = core.lzGasLookup(CrossChainSignalType.REFUND_COMPLETE);
        assertEq(gas, 888888);

        vm.stopPrank();
    }

    function test_Cannot_SetLzBaseGas_NotOwner() public {
        vm.expectRevert();
        core.setLzBaseGas(CrossChainSignalType.MINT, 888888);
    }

    /* =========================================================== */
    /*  ====================    getters   ======================   */
    /* =========================================================== */
    function test_GetRegisteredSliceTokens() public view {
        address[] memory tokens = core.getRegisteredSliceTokens();
        assertEq(2, tokens.length);
        assertEq(tokens[0], address(token));
        assertEq(tokens[1], address(ccToken));
    }

    function test_GetRegisteredSliceToken() public view {
        address _token = core.getRegisteredSliceToken(0);
        assertEq(address(token), _token);
    }

    function test_GetRegisteredSliceTokensCount() public view {
        assertEq(2, core.getRegisteredSliceTokensCount());
    }

    function test_CanCreateSlice() public view {
        assertTrue(core.canCreateSlice(dev));
        assertFalse(core.canCreateSlice(users[2]));
    }

    /* =========================================================== */
    /*  ==================    third party   ====================   */
    /* =========================================================== */
    function test_SafeERC20_RevertOnTransferFalse() public {
        vm.startPrank(dev);
        Position memory posR =
            Position({chainId: 1, token: 0xE41d2489571d322189246DaFA5ebDe1F4699F498, decimals: 18, units: 10 ether});

        positions.push(posR);

        (address sCore, address sToken) = deployTestContracts(ChainSelect.MAINNET, "Test2");
        core = SliceCore(payable(sCore));
        token = SliceToken(payable(sToken));

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);
        uint128[] memory fees;
        vm.expectRevert();
        token.mint(1 ether, fees);
        vm.stopPrank();
    }

    function test_Cannot_SendLzMessage() public {
        bytes32 mintId = _prepareCrossChainRefund();

        address polygonCore = _doFailedMintOnPolygon(mintId);

        // send the response msg
        // create cross chain signal
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT_COMPLETE,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits,
            value: 0
        });
        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = _ccsResponse2;
        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        vm.expectRevert();
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));
    }

    /* =========================================================== */
    /*  ====================   helpers   =======================   */
    /* =========================================================== */
    function bytes32ToHexString(bytes32 _bytes32) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = hexChars[uint256(uint8(_bytes32[i] >> 4))];
            str[1 + i * 2] = hexChars[uint256(uint8(_bytes32[i] & 0x0f))];
        }
        return string(str);
    }

    function bytesToHexString(bytes memory _bytes) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(_bytes.length * 2);
        for (uint256 i = 0; i < _bytes.length; i++) {
            str[i * 2] = hexChars[uint256(uint8(_bytes[i] >> 4))];
            str[1 + i * 2] = hexChars[uint256(uint8(_bytes[i] & 0x0f))];
        }
        return string(str);
    }

    function _estimateFee(address polygonCore, CrossChainSignalType type1, CrossChainSignalType typeRes)
        private
        returns (address, uint256, uint128[] memory, uint256[] memory)
    {
        uint128[] memory fees = new uint128[](1);

        selectPolygon();
        if (polygonCore == address(0)) {
            (polygonCore,) = deployTestContracts(ChainSelect.POLYGON, "");
        }

        LZFeeEstimator feeEstimatorPolygon = new LZFeeEstimator(
            SliceCore(payable(polygonCore)),
            SliceCore(payable(polygonCore)).chainInfo(),
            ILayerZeroEndpointV2(getAddress("polygon.layerZeroEndpoint"))
        );
        uint256 polygonFee = feeEstimatorPolygon.estimateLzFeeCompleted(ccPositions, typeRes, 1);
        fees[0] = uint128(polygonFee);

        selectMainnet();

        vm.deal(dev, 100 ether);

        LZFeeEstimator feeEstimator =
            new LZFeeEstimator(core, core.chainInfo(), ILayerZeroEndpointV2(getAddress("polygon.layerZeroEndpoint")));

        uint256[] memory feesForMsgs = feeEstimator.estimateLzFee(address(ccToken), type1, fees);

        uint256 feeTotal;
        for (uint256 i = 0; i < feesForMsgs.length; i++) {
            feeTotal += feesForMsgs[i];
        }

        return (polygonCore, feeTotal, fees, feesForMsgs);
    }

    function _mintCrossChain(uint8 length) public returns (bytes32, address) {
        Position[] memory _positions = ccPosCreator.getCCPositions(length);

        for (uint256 i = 1; i < _positions.length; i++) {
            ccPositions.push(_positions[i]);
        }
        vm.startPrank(dev);

        address ccTokenManyPos = core.createSlice("CCSlice", "CCS", ccPositions);
        ccToken = SliceToken(ccTokenManyPos);

        (address pCore, uint256 feeTotal, uint128[] memory fees, uint256[] memory feesForMsgs) =
            _estimateFee(address(0), CrossChainSignalType.MINT, CrossChainSignalType.MINT_COMPLETE);
        address polygonCore = pCore;

        bytes32 mintId = ccToken.mint{value: feeTotal}(1 ether, toUint128Array(feesForMsgs));
        assertNotEq(bytes32(0), mintId);

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: mintId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.MINT,
                success: false,
                user: dev,
                underlying: ccPositions[i].token,
                units: wmaticUnits,
                value: i == 0 ? feesForMsgs[0] : 0
            });

            ccsMsgs[i] = ccs;
        }

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        makePersistent(address(ccToken));

        _mintCrossChainPolygonPartComplex(polygonCore, origin, ccsEncoded, mintId, 1 ether, fees[0]);

        return (mintId, polygonCore);
    }

    function _mintCrossChainFuzz(uint256 sliceTokenAmount, uint8 length)
        internal
        returns (bytes32 mintId, address polygonCore)
    {
        Position[] memory _positions = ccPosCreator.getCCPositions(length);

        for (uint256 i = 1; i < _positions.length; i++) {
            ccPositions.push(_positions[i]);
        }
        vm.startPrank(dev);

        ccToken = SliceToken(core.createSlice("CCSlice", "CCS", ccPositions));

        (address pCore, uint256 feeTotal, uint128[] memory fees, uint256[] memory feesForMsgs) =
            _estimateFee(address(0), CrossChainSignalType.MINT, CrossChainSignalType.MINT_COMPLETE);
        polygonCore = pCore;

        mintId = ccToken.mint{value: feeTotal}(sliceTokenAmount, toUint128Array(feesForMsgs));
        assertNotEq(bytes32(0), mintId);

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: mintId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.MINT,
                success: false,
                user: dev,
                underlying: ccPositions[i].token,
                units: TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18),
                value: i == 0 ? feesForMsgs[0] : 0
            });

            ccsMsgs[i] = ccs;
        }
        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        makePersistent(address(ccToken));

        _mintCrossChainPolygonPartComplex(
            polygonCore,
            Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1}),
            ccsEncoded,
            mintId,
            sliceTokenAmount,
            fees[0]
        );
    }

    function _createOriginResp(address polygonCore) internal pure returns (Origin memory) {
        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});
        return originResponse;
    }

    function _prepareCrossChainRefund() private returns (bytes32 mintId) {
        vm.startPrank(dev);

        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            1 ether // 0.1 wETH
        );

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);

        ccPositions[0] = wethPosition;
        ccPositions.push(ccPos);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);
        weth.approve(address(ccToken), 10 ether);
        weth.approve(address(core), 10 ether);

        // run the cross-chain flow
        deal(address(usdc), dev, 10 ether);
        deal(address(weth), dev, 1 ether);

        vm.deal(dev, 100 ether);

        uint128[] memory fees = new uint128[](1);
        fees[0] = 18561664197127658;

        mintId = ccToken.mint{value: 18561664197127658}(1 ether, fees);
        assertNotEq(bytes32(0), mintId);

        vm.stopPrank();
    }

    function _doFailedMintOnPolygon(bytes32 mintId) private returns (address) {
        vm.startPrank(dev);
        // prepare cross chain logic
        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits,
            value: 0
        });

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = ccs;
        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        makePersistent(address(ccToken));

        (address polygonCore,) = deployTestContracts(ChainSelect.POLYGON, "");

        (,, uint128[] memory fees,) =
            _estimateFee(polygonCore, CrossChainSignalType.MINT, CrossChainSignalType.MINT_COMPLETE);

        // change network
        selectPolygon();

        // make sure that the user has no wmatic on dst chain
        uint256 balance = wmaticPolygon.balanceOf(dev);
        assertEq(0, balance);

        vm.stopPrank();

        deal(getAddress("polygon.layerZeroEndpoint"), 100 ether);

        // send the cross-chain msg: call lzReceive
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive{value: fees[0]}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        return polygonCore;
    }

    function _handleMainnetResponseOnFailedMint(
        bytes32 mintId,
        address polygonCore,
        uint256 sliceTokenAmount,
        uint8 positionsLength
    ) private {
        selectMainnet();
        (, uint256 feeTotal, uint128[] memory fees, uint256[] memory feesForMsgs) =
            _estimateFee(polygonCore, CrossChainSignalType.REFUND, CrossChainSignalType.REFUND_COMPLETE);

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](positionsLength);

        for (uint256 i = 0; i < positionsLength; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: mintId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.REFUND,
                success: false,
                user: dev,
                underlying: ccPositions[i].token,
                units: TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18),
                value: i == 0 ? feesForMsgs[0] : 0
            });

            ccsMsgs[i] = ccs;
        }

        for (uint256 i = uint8(failAtIdx); i < ccsMsgs.length - 1; i++) {
            ccsMsgs[i] = ccsMsgs[i + 1];
        }
        CrossChainSignal[] memory ccsMsgs2 = new CrossChainSignal[](positionsLength - 1);
        for (uint256 i = 0; i < positionsLength - 1; i++) {
            ccsMsgs2[i] = ccsMsgs[i];
        }

        bytes memory ccsEncoded = abi.encode(ccsMsgs2);

        ccToken.refund{value: feeTotal}(mintId, toUint128Array(feesForMsgs));

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo2 = ccToken.getMint(mintId);
        bool isStateRefunding = txInfo2.state == TransactionState.REFUNDING;
        assertEq(isStateRefunding, true);

        Origin memory origin2 = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});
        selectPolygon();
        deal(getAddress("polygon.layerZeroEndpoint"), fees[0]);
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive{value: fees[0]}(origin2, bytes32(0), ccsEncoded, dev, bytes(""));

        selectMainnet();
        for (uint256 i = 0; i < positionsLength - 1; i++) {
            ccsMsgs2[i].ccsType = CrossChainSignalType.REFUND_COMPLETE;
            ccsMsgs2[i].success = true;
        }
        bytes memory ccsEncoded2 = abi.encode(ccsMsgs2);

        Origin memory origin3 =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        deal(getAddress("polygon.layerZeroEndpoint"), 0.1 ether);
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive{value: 0.1 ether}(origin3, bytes32(0), ccsEncoded2, dev, bytes(""));
    }

    function _mintCrossChainPolygonPartComplex(
        address polygonCore,
        Origin memory origin,
        bytes memory ccsEncoded,
        bytes32 mintId,
        uint256 sliceTokenAmount,
        uint128 fee
    ) internal {
        selectPolygon();
        uint256 amountOut = TokenAmountUtils.calculateAmountOutMin(sliceTokenAmount, wmaticUnits, 18);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            if (failAtIdx == int8(int256(i))) {
                continue;
            }
            deal(ccPositions[i].token, dev, amountOut);
            IERC20(ccPositions[i].token).approve(polygonCore, amountOut);
        }

        IOAppCore(polygonCore).setPeer(30101, bytes32(uint256(uint160(address(core)))));
        deal(polygonCore, 0);

        deal(getAddress("polygon.layerZeroEndpoint"), fee);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive{value: fee}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        for (uint256 i = 0; i < ccPositions.length; i++) {
            if (failAtIdx != int8(int256(i))) {
                uint256 bal = IERC20(ccPositions[i].token).balanceOf(address(polygonCore));
                assertEq(amountOut, bal);
            }
            {
                CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
                    id: mintId,
                    srcChainId: uint32(block.chainid),
                    ccsType: CrossChainSignalType.MINT_COMPLETE,
                    success: failAtIdx != int8(int256(i)),
                    user: dev,
                    underlying: ccPositions[i].token,
                    units: amountOut,
                    value: 0
                });

                ccsMsgs[i] = _ccsResponse2;
            }
        }

        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        selectMainnet();
        if (failAtIdx == -1) {
            vm.expectEmit(true, true, true, false);
            emit ISliceCore.UnderlyingAssetsCollected(address(ccToken), sliceTokenAmount, dev);
        }

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(_createOriginResp(polygonCore), bytes32(0), ccsEncoded2, dev, bytes(""));
    }

    struct Packet {
        uint8 fill;
        uint64 nonce;
        uint32 srcEid;
        bytes32 sender;
        uint32 dstEid;
        bytes32 receiver;
        bytes32 guid;
        bytes message;
    }

    function decodePacket(bytes memory data) public pure returns (Packet memory) {
        require(data.length >= 145, "Data too short");

        uint8 fill;
        uint64 nonce;
        uint32 srcEid;
        bytes32 sender;
        uint32 dstEid;
        bytes32 receiver;
        bytes32 guid;
        bytes memory message;

        assembly {
            fill := mload(add(data, 1))
            nonce := mload(add(data, 9))
            srcEid := mload(add(data, 13))
            sender := mload(add(data, 45))
            dstEid := mload(add(data, 49))
            receiver := mload(add(data, 81))
            guid := mload(add(data, 113))
        }

        uint256 givenIdx = 113;
        uint256 messageLength = data.length - givenIdx;
        message = new bytes(messageLength);
        for (uint256 i = 0; i < messageLength; i++) {
            message[i] = data[givenIdx + i];
        }

        return Packet(fill, nonce, srcEid, sender, dstEid, receiver, guid, message);
    }

    function toUint128Array(uint256[] memory arr) internal pure returns (uint128[] memory) {
        uint128[] memory _arr = new uint128[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            _arr[i] = uint128(arr[i]);
        }
        return _arr;
    }
}
