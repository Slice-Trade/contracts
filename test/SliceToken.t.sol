// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";
import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";

import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/ChainInfo.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

import "./mocks/SliceCoreMock.sol";
import "../src/libs/SliceTokenDeployer.sol";

contract SliceTokenTest is Helper {
    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720

    SliceCore core;
    SliceToken token;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public link;

    IERC20 wmaticPolygon;

    Position[] public positions;

    uint256 maxEstWethPrice = 40000000000; // 40000 usdc
    uint256 maxEstLinkPrice = 45000000000; // 45000 usdc

    uint256 constant MAX_ESTIMATED_PRICE = 160000000000; // 160000 USDC

    uint256[] public maxEstimatedPrices;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    bytes[] public routes;

    bytes public usdcWethRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001";
    bytes public usdcLinkRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001C40D16476380e4037e6b1A2594cAF6a6cc8Da96704C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200C40D16476380e4037e6b1A2594cAF6a6cc8Da96700";

    SliceToken ccToken;
    Position[] public ccPositions;

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet(MAINNET_BLOCK_NUMBER);
        forkPolygon(POLYGON_BLOCK_NUMBER);
        selectMainnet();

        usdc = IERC20(getAddress("mainnet.usdc"));
        weth = IWETH(getAddress("mainnet.weth"));
        link = IERC20(getAddress("mainnet.link"));

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

        positions.push(wethPosition);
        positions.push(linkPosition);

        ChainInfo chainInfo = new ChainInfo();

        SliceTokenDeployer deployer = new SliceTokenDeployer();

        core = new SliceCore(
            getAddress("mainnet.layerZeroEndpoint"),
            address(chainInfo),
            address(deployer),
            dev
        );

        usdcWethRoute = abi.encodePacked(usdcWethRoute, address(core));
        usdcLinkRoute = abi.encodePacked(usdcLinkRoute, address(core));

        routes.push(usdcWethRoute);
        routes.push(usdcLinkRoute);

        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(dev, true);

        address tokenAddr = core.createSlice("Slice Token", "SC", positions);
        token = SliceToken(tokenAddr);

        usdc.approve(address(core), MAX_ESTIMATED_PRICE * 10);
        usdc.approve(address(token), MAX_ESTIMATED_PRICE * 10);

        Position memory ccPos = Position(137, 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, 18, 95000000000000000000);
        ccPositions.push(ccPos);
        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   =================    mintComplete   ==================    */
    /* =========================================================== */
    function test_MintComplete() public {
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);
        // call mint
        bytes32 mintId = sliceToken.mint(2);

        // verify that SliceMinted event emitted
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMinted(dev, 2);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        coreMock.mintComplete(mintId, address(sliceToken));

        // verify that slice token balance of user is increased
        uint256 sliceTokenBalance = sliceToken.balanceOf(dev);
        assertEq(2, sliceTokenBalance);
        vm.stopPrank();
    }

    function test_Cannot_MintComplete_NotAuthorized() public {
        // create a new Slice token
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        // call mint
        bytes32 mintId = sliceToken.mint(1 ether);
        vm.stopPrank();

        vm.startPrank(users[1]);
        vm.expectRevert(bytes4(keccak256("NotSliceCore()")));
        // verify that mintComplete fails from non dev address
        sliceToken.mintComplete(mintId);
        vm.stopPrank();
    }

    function test_Cannot_MintComplete_NotOpen() public {
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        bytes32 mintId = sliceToken.mint(2);

        coreMock.mintComplete(mintId, address(sliceToken));

        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        coreMock.mintComplete(mintId, address(sliceToken));
    }

    function test_Cannot_MintComplete_InvalidMintID() public {
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);
        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        // verify that mintComplete fails with invalid mint ID
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        coreMock.mintComplete(bytes32(0), address(sliceToken));
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   =====================    mint   ======================    */
    /* =========================================================== */
    function test_mint() public {
        vm.startPrank(dev);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);

        vm.expectEmit(true, true, true, false);
        emit ISliceCore.UnderlyingAssetsProcured(address(token), 1 ether, dev);

        vm.expectEmit(true, true, true, false);
        emit IERC20.Transfer(address(0), dev, 1 ether);

        bytes32 mintId = token.mint(1 ether);
        assertNotEq(bytes32(0), mintId);

        uint256 tokenBalance = token.balanceOf(dev);
        assertEq(tokenBalance, 1 ether);

        uint256 wethBalance = weth.balanceOf(dev);
        uint256 linkBalance = link.balanceOf(dev);
        assertEq(0, wethBalance);
        //assertEq(0, wbtcBalance);
        assertEq(0, linkBalance);

        uint256 coreWethBalance = weth.balanceOf(address(core));
        uint256 coreLinkBalance = link.balanceOf(address(core));
        assertEq(wethUnits, coreWethBalance);
        assertEq(linkUnits, coreLinkBalance);

        vm.stopPrank();
    }

    function test_CannotMint_ZeroTokenQuantity() public {
        vm.expectRevert(bytes4(keccak256("ZeroTokenQuantity()")));
        token.mint(0);
    }

    function test_CannotMint_InsufficientTokenQuantity() public {
        Position memory _position = Position({
            chainId: 1,
            token: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            decimals: 8,
            units: 100000000
        });
        positions.push(_position);

        SliceToken sliceToken = new SliceToken("TEST 3", "T3", positions, address(core));
        vm.expectRevert(bytes4(keccak256("InsufficientTokenQuantity()")));
        sliceToken.mint(1);
    }

    /* =========================================================== */
    /*    ===================    redeem    ====================    */
    /* =========================================================== */
    function test_Redeem() public {
        vm.startPrank(dev);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);

        token.mint(1 ether);

        uint256 balanceBeforeRedeem = token.balanceOf(dev);
        assertEq(1000000000000000000, balanceBeforeRedeem);

        vm.expectEmit(true, true, true, false);
        emit IERC20.Transfer(dev, address(0), 1000000000000000000);

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceRedeemed(dev, 1000000000000000000);

        bytes32 redeemId = token.redeem(1000000000000000000);

        assertNotEq(bytes32(0), redeemId);
        uint256 balanceAfterRedeem = token.balanceOf(dev);
        assertEq(0, balanceAfterRedeem);
        vm.stopPrank();
    }

    function test_Cannot_Redeem_InsufficientBalance() public {
        vm.expectRevert(bytes4(keccak256("InsufficientBalance()")));
        token.redeem(1);
    }

    function test_CannotRedeem_InsufficientTokenQuantity() public {
        Position memory _position = Position({
            chainId: 1,
            token: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            decimals: 8,
            units: 100000000
        });
        positions.push(_position);

        SliceToken sliceToken = new SliceToken("TEST 3", "T3", positions, address(core));
        vm.expectRevert(bytes4(keccak256("InsufficientTokenQuantity()")));
        sliceToken.redeem(1);
    }

    function test_Transfer() public {
        vm.startPrank(dev);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);

        token.mint(1 ether);

        token.transfer(users[1], 1 ether);
    }

    function test_Cannot_Transfer_AmountLocked() public {
        vm.startPrank(dev);
        deal(address(core), 1 ether);
        /* CROSS_CHAIN */
        uint256 maxWMaticPrice = 100000000; //100usdc
        uint256 wmaticUnits = 95000000000000000000; // 95matic

        bytes memory usdcWmaticRoute =
            hex"012791Bca1f2de4661ED88A30C99A7a9449Aa8417402555500cd353F79d9FADe311fC3119B841e1f456b54e85800eeb3e0999D01f0d1Ed465513E414725a357F6ae4ffff0121988C9CFD08db3b5793c2C6782271dC9474925100eeb3e0999D01f0d1Ed465513E414725a357F6ae4";
        routes.push(usdcWmaticRoute);

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        positions.push(ccPos);

        maxEstimatedPrices.push(maxWMaticPrice);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);
        // call mint
        bytes32 mintId = sliceToken.mint(1000000000000000000);

        coreMock.mintComplete(mintId, address(sliceToken));

        sliceToken.redeem(1000000000000000000);

        vm.expectRevert(bytes4(keccak256("AmountLocked()")));
        sliceToken.transfer(users[1], 1000000000000000000);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ================    redeemComplete   =================    */
    /* =========================================================== */
    function test_RedeemComplete() public {
        // mint some slice tokens
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);
        bytes32 _mintID = sliceToken.mint(1000000000000000000);

        coreMock.mintComplete(_mintID, address(sliceToken));

        // call redeem underlying
        bytes32 redeemId = sliceToken.redeem(1000000000000000000);

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceRedeemed(dev, 1000000000000000000);

        coreMock.redeemComplete(redeemId, address(sliceToken));

        uint256 sliceBalance = sliceToken.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function test_Cannot_RedeemComplete_NotAuthorized() public {
        vm.expectRevert(bytes4(keccak256("NotSliceCore()")));
        token.redeemComplete(bytes32(0));
    }

    function test_Cannot_RedeemComplete_InvalidRedeemID() public {
        vm.startPrank(dev);
        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, dev);
        vm.expectRevert(bytes4(keccak256("RedeemIdDoesNotExist()")));
        sliceToken.redeemComplete(bytes32(0));
        vm.stopPrank();
    }

    function test_Cannot_RedeemComplete_InvalidTransactionState() public {
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);
        bytes32 _mintID = sliceToken.mint(1000000000000000000);

        coreMock.mintComplete(_mintID, address(sliceToken));

        // call redeem underlying
        bytes32 redeemId = sliceToken.redeem(1000000000000000000);

        coreMock.redeemComplete(redeemId, address(sliceToken));

        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        coreMock.redeemComplete(redeemId, address(sliceToken));
    }

    /* =========================================================== */
    /*   ===================   mintFailed   ====================   */
    /* =========================================================== */
    function test_mintFailed() public {
        // start the cross chain mint from the token
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));

        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        // switch to slice core
        vm.prank(address(core));

        // make sure that event is emitted
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMintFailed(dev, 1 ether);

        // call mint failed for the mint ID
        ccToken.mintFailed(mintID);

        // make sure that state is updated to FAILED
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintID);
        bool isStateFailed = txInfo.state == TransactionState.FAILED;
        assertTrue(isStateFailed);
    }

    function test_mintFailed_StateAlreadyFailed() public {
        // make sure that if the tx state is FAILED the function returns and does not revert
        // start the cross chain mint from the token
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));

        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        // switch to slice core
        vm.prank(address(core));

        // call mint failed for the mint ID
        ccToken.mintFailed(mintID);

        vm.prank(address(core));
        // make sure call goes through again
        ccToken.mintFailed(mintID);
    }

    function test_Cannot_MintFailed_NotSliceCore() public {
        // make sure only slice core can call
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("NotSliceCore()")));
        ccToken.mintFailed(mintID);
    }

    function test_Cannot_MintFailed_MintIdDoesNotExist() public {
        // make sure it fails when invalid mint id
        vm.prank(address(core));
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        token.mintFailed(bytes32(0));
    }

    function test_Cannot_MintFailed_InvalidTransactionState() public {
        // make sure it fails when not open state
        // make sure only slice core can call
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        vm.startPrank(address(core));
        ccToken.mintComplete(mintID);

        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        ccToken.mintFailed(mintID);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ====================    refund    ====================    */
    /* =========================================================== */
    function test_Refund() public {
        // start a mint
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        // call mint failed
        vm.prank(address(core));
        ccToken.mintFailed(mintID);

        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintID,
            srcChainId: uint32(137),
            ccsType: CrossChainSignalType.MINT_COMPLETE,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: 1 ether
        });
        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded, dev, bytes(""));

        // call refund
        vm.prank(dev);
        ccToken.refund(mintID);

        // make state is updated
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintID);
        bool isMintStateUpdated = txInfo.state == TransactionState.REFUNDED;
        assertTrue(isMintStateUpdated);
    }

    function test_Cannot_Refund_MintIdDoesNotExist() public {
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        token.refund(bytes32(0));
    }

    function test_Cannot_Refund_InvalidTransactionState() public {
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);

        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        ccToken.refund(mintID);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*  ==================   refundComplete   ==================   */
    /* =========================================================== */
    function test_RefundComplete() public {
        // start a mint
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        // call mint failed
        vm.prank(address(core));
        ccToken.mintFailed(mintID);

        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintID,
            srcChainId: uint32(137),
            ccsType: CrossChainSignalType.MINT_COMPLETE,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: 1 ether
        });

        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](1);
        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded, dev, bytes(""));

        // make sure event is emitted
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.RefundCompleted(dev, 1 ether);

        // call refund
        vm.prank(dev);
        ccToken.refund(mintID);

        // make sure state updated
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintID);

        bool isMintStateUpdated = txInfo.state == TransactionState.REFUNDED;

        assertTrue(isMintStateUpdated);
    }

    function test_Cannot_RefundComplete_NotSliceCore() public {
        vm.expectRevert(bytes4(keccak256("NotSliceCore()")));
        ccToken.refundComplete(bytes32(0));
    }

    function test_Cannot_RefundComplete_MintIdDoesNotExist() public {
        vm.prank(address(core));
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        ccToken.refundComplete(bytes32(0));
    }

    function test_Cannot_RefundComplete_InvalidTransactionState() public {
        // start a mint
        deal(address(usdc), dev, 10 ether);
        vm.startPrank(dev);
        vm.deal(dev, 100 ether);
        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);
        IOAppCore(core).setPeer(30109, bytes32(uint256(uint160(address(core)))));
        bytes32 mintID = ccToken.mint(1 ether);
        vm.stopPrank();

        vm.prank(address(core));
        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        ccToken.refundComplete(mintID);
    }

    /* =========================================================== */
    /*  =============   setCategoryAndDescription   =============  */
    /* =========================================================== */
    function test_SetCategoryAndDescription() public {
        token.setCategoryAndDescription("Test", "Test description");
        string memory category = token.category();
        assertEq("Test", category);
        string memory description = token.description();
        assertEq("Test description", description);
    }

    function test_Cannot_SetCategoryAndDescription_AlreadySet() public {
        token.setCategoryAndDescription("Test", "Test description");
        vm.expectRevert(bytes4(keccak256("AlreadySet()")));
        token.setCategoryAndDescription("Test", "Test description");
    }

    /* =========================================================== */
    /*  ====================   getPosAtIdx   ===================   */
    /* =========================================================== */
    function test_GetPosAtIdx() public view {
        Position memory pos = token.getPosAtIdx(0);

         assertEq(1, pos.chainId);
         assertEq(address(weth), pos.token);
         assertEq(wethUnits, pos.units);
    }

    function test_Cannot_GetPosAtIdx_InvalidIndex() public {
        vm.expectRevert();
        token.getPosAtIdx(5);
    }
}
