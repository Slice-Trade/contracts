// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/Route.sol";
import "../src/utils/ChainInfo.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

contract SliceCoreTest is Helper {
    SliceCore core;
    SliceToken token;

    SliceToken ccToken;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public wbtc;
    IERC20 public link;

    IERC20 public wmaticPolygon;

    Position[] public positions;

    uint256 maxEstWethPrice = 40000000000; // 40000 usdc
    uint256 maxEstWbtcPrice = 75000000000; // 75000 usdc
    uint256 maxEstLinkPrice = 45000000000; // 45000 usdc

    uint256 constant MAX_ESTIMATED_PRICE = 160000000000; // 160000 USDC

    uint256[] public maxEstimatedPrices;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public wbtcUnits = 100000000; // 1 wBTC (8 decimals)
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    uint256[] public wrongPrices;

    bytes[] public routes;

    bytes public usdcWethRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa0014b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";
    bytes public usdcWbtcRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001CEfF51756c56CeFFCA006cD410B03FFC46dd3a5804C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200CEfF51756c56CeFFCA006cD410B03FFC46dd3a58004b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";
    bytes public usdcLinkRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001C40D16476380e4037e6b1A2594cAF6a6cc8Da96704C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200C40D16476380e4037e6b1A2594cAF6a6cc8Da967004b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";

    
    /* CROSS_CHAIN */
    uint256 maxWMaticPrice = 100000000; //100usdc
    uint256 wmaticUnits = 95000000000000000000; // 95matic

    uint256[] public maxEstCCPrices;
    Position[] public ccPositions;
    bytes[] public ccRoutes;
    bytes public usdcWmaticRoute = hex"012791Bca1f2de4661ED88A30C99A7a9449Aa8417402555500cd353F79d9FADe311fC3119B841e1f456b54e85800eeb3e0999D01f0d1Ed465513E414725a357F6ae4ffff0121988C9CFD08db3b5793c2C6782271dC9474925100eeb3e0999D01f0d1Ed465513E414725a357F6ae4";
    
    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet(19518913);

        usdc = IERC20(getAddress("mainnet.usdc"));
        wbtc = IERC20(getAddress("mainnet.wbtc"));
        link = IERC20(getAddress("mainnet.link"));
        weth = IWETH(getAddress("mainnet.weth"));

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        maxEstimatedPrices.push(maxEstWethPrice);
        maxEstimatedPrices.push(maxEstWbtcPrice);
        maxEstimatedPrices.push(maxEstLinkPrice);

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);
        vm.startPrank(dev);

        // create positions
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            wethUnits // 0.1 wETH
        );

        Position memory wbtcPosition = Position(
            1, // mainnet
            address(wbtc), // wrapped BTC
            wbtcUnits // 0.01 wBTC
        );

        Position memory linkPosition = Position(
            1, // mainnet
            address(link), // chainlink
            linkUnits // 20 LINK
        );

        positions.push(wethPosition);
        positions.push(wbtcPosition);
        positions.push(linkPosition);

        routes.push(usdcWethRoute);
        routes.push(usdcWbtcRoute);
        routes.push(usdcLinkRoute);

        Route routeProcessorHelper = new Route(
            getAddress("mainnet.v2Factory"),
            getAddress("mainnet.v3Factory"),
            getAddress("mainnet.routeProcessor"),
            address(weth)
        );

        ChainInfo chainInfo = new ChainInfo();

        core = new SliceCore(
            address(usdc),
            getAddress("mainnet.sushiXSwap"),
            getAddress("mainnet.stargateAdapter"),
            getAddress("mainnet.axelarAdapter"),
            address(0),
            getAddress("mainnet.layerZeroEndpoint"), // TODO
            address(chainInfo)
        );
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(dev, true);

        routeProcessorHelper.setSliceCore(address(core));

        address tokenAddr = core.createSlice("Slice Token", "SC", positions);
        token = SliceToken(tokenAddr);

        usdc.approve(address(core), MAX_ESTIMATED_PRICE * 10);
        usdc.approve(address(token), MAX_ESTIMATED_PRICE * 10);

        Position memory ccPos = Position(
            137,
            address(wmaticPolygon),
            wmaticUnits
        );

        ccPositions.push(ccPos);

        ccRoutes.push(usdcWmaticRoute);

        maxEstCCPrices.push(maxWMaticPrice);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function testCreateSlice() public {
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

    function testCannotCreateSlice_NotAuthorized() public {
        vm.prank(dev);
        core.changeSliceTokenCreationEnabled(true);

        // call create Slice token from an unverified address
        vm.prank(users[2]);
        // verify that transaction fails with the correct revert message
        vm.expectRevert("SliceCore: Unauthorized caller");
        core.createSlice("Test Token", "TT", positions);
    }

    function testCannotCreateSlice_CreationNotEnabled() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(false);
        vm.expectRevert("SliceCore: Slice token creation disabled");
        core.createSlice("Test Token", "TT", positions);
        vm.stopPrank();
    }
    /* =========================================================== */
    /*   ===========   purchaseUnderlyingAssets   =============    */
    /* =========================================================== */
    function testPurchaseUnderlyingAssets() public {
        vm.startPrank(dev);
        // call mint -> call purchase underlying assets

        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsPurchased(address(token), 1000000000000000000, dev);

        token.mint(1000000000000000000, maxEstimatedPrices, routes);

        // verify that the assets are purhased
        uint256 wethBalance = weth.balanceOf(address(token));
        uint256 wbtcBalance = wbtc.balanceOf(address(token));
        uint256 linkBalance = link.balanceOf(address(token));

        assertGe(wethBalance, wethUnits);
        assertGe(wbtcBalance, wbtcUnits);
        assertGe(linkBalance, linkUnits);

        console.log("wETH Balance: ");
        console.log(wethBalance);

        console.log("wBTC Balance: ");
        console.log(wbtcBalance);

        console.log("Link balance: ");
        console.log(linkBalance);

        vm.stopPrank();
    }

    function testPurchaseUnderlyingAssets_Multichain() public {
        vm.startPrank(dev);

        vm.deal(dev, 100 ether);

        console.log(dev.balance);
        (bool success, ) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        ccToken.mint(1000000000000000000, maxEstCCPrices, ccRoutes);

        vm.stopPrank();
    }

    function testCannotPurchaseUnderlyingAssets_NotRegistedSliceToken() public {
        // verify that it reverts with the correct revert msg
        vm.expectRevert("SliceCore: Only registered Slice token can call");
        // call purchaseUnderlying from a non-registered address
        core.purchaseUnderlyingAssets(bytes32(0), 1, maxEstimatedPrices, routes);
    }

    // TODO: cannot purchase - invalid mint id

    /* =========================================================== */
    /*   =============    rebalanceUnderlying   ===============    */
    /* =========================================================== */
    function testRebalanceUnderlying() public {
        // mint some tokens
        vm.startPrank(dev);
        token.mint(2, maxEstimatedPrices, routes);

        // rebalance
        positions[0].units = 130346080000000000; // increase by a hundred bucks
        positions[1].units = 8415120000000000; // decrease by a hundred bucks

        // verify that event has been emitted
        vm.expectEmit(true, false, false, false);
        emit ISliceCore.UnderlyingAssetsRebalanced(address(token));
        token.rebalance(positions);

        // verify that positions info is updated
        Position[] memory newPositions = token.getPositions();
        assertEq(130346080000000000, newPositions[0].units);
        assertEq(8415120000000000, newPositions[1].units);

        // verify that underlying assets have been sold/bought correctly
        uint256 wethBalance = weth.balanceOf(address(token));
        uint256 wbtcBalance = wbtc.balanceOf(address(token));
        assertEq(wethBalance, newPositions[0].units * 2);
        assertEq(wbtcBalance, newPositions[1].units * 2);
        vm.stopPrank();
    }

    function testCannotRebalanceUnderlying_NotAuthorized() public {
        // verify that it reverts with correct reason
        vm.expectRevert("SliceCore: Only registered Slice token can call");
        // call rebalance from non-owner address
        core.rebalanceUnderlying(bytes32(0), positions);
    }

    function testCannotRebalanceUnderlying_InvalidUnits() public {
        vm.startPrank(dev);
        // call rebalance with invalid values (can't sell enough to buy the other)
        positions[0].units = 2000000000000000000;
        positions[1].units = 2000000000000000000;
        // verify that it reverts with the correct reason
        vm.expectRevert("SliceCore: Invalid positions after rebalance");
        token.rebalance(positions);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==============    redeemUnderlying    ================    */
    /* =========================================================== */
    function testRedeemUnderlying() public {
        // mint some slice tokens
        vm.startPrank(dev);
        token.mint(2, maxEstimatedPrices, routes);

        // call redeem underlying
        token.redeem(2);

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);

        uint256 wethTokenbalance = weth.balanceOf(address(token));
        uint256 wbtcTokenbalance = wbtc.balanceOf(address(token));
        assertEq(0, wethTokenbalance);
        assertEq(0, wbtcTokenbalance);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function testCannotRedeemUnderlying_NotAuthorized() public {
        // verify that it reverts with the correct reason
        vm.expectRevert("SliceCore: Only registered Slice token can call");
        // call redeem from not registered slice token
        core.redeemUnderlying(bytes32(0), SliceTransactionInfo(bytes32(0), 0, address(0), TransactionState.UNREGISTERED, bytes("")));
    }

    /* =========================================================== */
    /*  =========   changeSliceTokenCreationEnabled   ===========  */
    /* =========================================================== */
    function testChangeSliceTokenCreationEnabled() public {
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

        vm.expectRevert("SliceCore: Slice token creation disabled");
        // verify that we cannot create slice tokens
        core.createSlice("New Test Token", "NTT", positions);
        vm.stopPrank();
    }

    function testCannotChangeSliceTokenCreationEnabled_NotAuthorized() public {
        vm.prank(users[2]);
        // verify that it reverts with the correct revert msg
        vm.expectRevert("0x118cdaa70000000000000000000000008ce502537d13f249834eaa02dde4781ebfe0d40f");
        // try changing enable/disable with non-owner address
        core.changeSliceTokenCreationEnabled(false);
    }
}


/* 
0x012791Bca1f2de4661ED88A30C99A7a9449Aa8417402555500cd353F79d9FADe311fC3119B841e1f456b54e85800eeb3e0999D01f0d1Ed465513E414725a357F6ae4ffff0121988C9CFD08db3b5793c2C6782271dC9474925100eeb3e0999D01f0d1Ed465513E414725a357F6ae4
01
2791Bca1f2de4661ED88A30C99A7a9449Aa84174
02
5555
00
cd353F79d9FADe311fC3119B841e1f456b54e858
00
eeb3e0999D01f0d1Ed465513E414725a357F6ae4

ffff
01
21988C9CFD08db3b5793c2C6782271dC94749251
00
eeb3e0999D01f0d1Ed465513E414725a357F6ae4
 */