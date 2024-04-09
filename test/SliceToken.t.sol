// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/Route.sol";
import "../src/utils/ChainInfo.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

import "./mocks/SliceCoreMock.sol";

contract SliceTokenTest is Helper {
    SliceCore core;
    SliceToken token;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public wbtc;
    IERC20 public link;

    Position[] public positions;

    uint256 maxEstWethPrice = 40000000000; // 40000 usdc
    uint256 maxEstWbtcPrice = 75000000000; // 75000 usdc
    uint256 maxEstLinkPrice = 45000000000; // 45000 usdc

    uint256 constant MAX_ESTIMATED_PRICE = 160000000000; // 160000 USDC

    uint256[] public maxEstimatedPrices;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public wbtcUnits = 100000000; // 1 wBTC (8 decimals)
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    bytes[] public routes;

    bytes public usdcWethRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa0014b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";
    bytes public usdcWbtcRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001CEfF51756c56CeFFCA006cD410B03FFC46dd3a5804C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200CEfF51756c56CeFFCA006cD410B03FFC46dd3a58004b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";
    bytes public usdcLinkRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001C40D16476380e4037e6b1A2594cAF6a6cc8Da96704C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200C40D16476380e4037e6b1A2594cAF6a6cc8Da967004b60d93e8BAECbBbE8955fe6Fe5AbD483e21502F";

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet(19518913);

        usdc = IERC20(getAddress("mainnet.usdc"));
        weth = IWETH(getAddress("mainnet.weth"));
        wbtc = IERC20(getAddress("mainnet.wbtc"));
        link = IERC20(getAddress("mainnet.link"));

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
            getAddress("mainnet.layerZeroEndpoint"),
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

        vm.stopPrank();
    }

    /* =========================================================== */
    /*    ==================      mint     ====================    */
    /* =========================================================== */
    function testMint() public {
        vm.startPrank(dev);

        uint256 balanceBefore = usdc.balanceOf(dev);

        // verify that purchase event in Core contract is emitted
        vm.expectEmit(true, true, true, false);
        emit ISliceCore.UnderlyingAssetsPurchased(address(token), 2, dev);

        // call mint
        bytes32 mintId = token.mint(2, maxEstimatedPrices, routes);

        // check that mint ID is properly recorded
        assertNotEq(bytes32(0), mintId);

        // verify that USDC is taken from user account
        uint256 balanceAfter = usdc.balanceOf(dev);
        uint256 expectedBalance = balanceBefore - MAX_ESTIMATED_PRICE;
        assertEq(expectedBalance, balanceAfter);

        vm.stopPrank();
    }

    function testCannotMint_NotEnoughMoney() public {
        // verify that correct revert message is emitted
        vm.startPrank(users[1]);

        usdc.approve(address(token), MAX_ESTIMATED_PRICE);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.mint(20000000000000000000, maxEstimatedPrices, routes);

        // verify that user Slice balance has not been increased
        uint256 sliceTokenBalance = token.balanceOf(users[1]);
        assertEq(0, sliceTokenBalance);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   =================    mintComplete   ==================    */
    /* =========================================================== */
    function testMintComplete() public {
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));
        
        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);
        // call mint
        bytes32 mintId = sliceToken.mint(2, maxEstimatedPrices, routes);

        // verify that SliceMinted event emitted
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMinted(dev, 2);

        coreMock.mintComplete(mintId, address(sliceToken));

        // verify that underlying assets are in the slice token
        uint256 wethBalance = weth.balanceOf(address(sliceToken));
        uint256 wbtcBalance = wbtc.balanceOf(address(sliceToken));
        uint256 linkBalance = link.balanceOf(address(sliceToken));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);
        assertEq(linkBalance, positions[2].units);

        // verify that slice token balance of user is increased
        uint256 sliceTokenBalance = sliceToken.balanceOf(dev);
        assertEq(2, sliceTokenBalance);
        vm.stopPrank();
    }

    function testCannotMintComplete_NotAuthorized() public {
        // create a new Slice token
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        // call mint
        bytes32 mintId = sliceToken.mint(2, maxEstimatedPrices, routes);
        vm.stopPrank();

        vm.startPrank(users[1]);
        vm.expectRevert("SliceToken: Only Slice Core can call");
        // verify that mintComplete fails from non dev address
        sliceToken.mintComplete(mintId);
        vm.stopPrank();
    }

    function testCannotMintComplete_NotOpen() public {
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        bytes32 mintId = sliceToken.mint(2, maxEstimatedPrices, routes);

        coreMock.mintComplete(mintId, address(sliceToken));

        vm.expectRevert("SliceToken: Transaction state is not open");
        coreMock.mintComplete(mintId, address(sliceToken));
    }

    function testCannotMintComplete_InvalidMintID() public {
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);
        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));

        coreMock.setToken(address(sliceToken));
        usdc.approve(address(sliceToken), MAX_ESTIMATED_PRICE * 10);

        // verify that mintComplete fails with invalid mint ID
        vm.expectRevert("SliceToken: Invalid mint ID");
        coreMock.mintComplete(bytes32(0), address(sliceToken));
        vm.stopPrank();
    }

    /* =========================================================== */
    /*    ==================    rebalance   ===================    */
    /* =========================================================== */
    function testRebalance() public {
        vm.prank(dev);
        bytes32 rebalanceId = token.rebalance(positions);
        assertNotEq(bytes32(0), rebalanceId);
    }

    function testCannotRebalance_NotAuthorized() public {
        // verify that reverts with correct msg
        vm.prank(users[1]);
        vm.expectRevert("SliceToken: Only contract owner can call");
        token.rebalance(positions);
    }

    /* =========================================================== */
    /*  ================   rebalanceComplete   =================   */
    /* =========================================================== */
    function testRebalanceComplete() public {
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));

        coreMock.setToken(address(sliceToken));

        // mint some slice tokens
        sliceToken.mint(2, maxEstimatedPrices, routes);

        positions[0].units = 130346080000000000; // increase by a hundred bucks
        positions[1].units = 8415120000000000; // decrease by a hundred bucks
        // call rebalance from token creator address
        bytes32 rebalanceId = sliceToken.rebalance(positions);

        // verify that positions only updates in rebalanceComplete call
        Position[] memory notUpdatedPositions = sliceToken.getPositions();
        assertEq(wethUnits, notUpdatedPositions[0].units);
        assertEq(wbtcUnits, notUpdatedPositions[1].units);

        vm.expectEmit(true, false, false, false);
        emit ISliceToken.SliceRebalanced(address(sliceToken));

        coreMock.rebalanceComplete(rebalanceId, address(sliceToken));

        // verify that positions info is updated in token
        Position[] memory updatedPositions = sliceToken.getPositions();
        assertEq(130346080000000000, updatedPositions[0].units);
        assertEq(8415120000000000, updatedPositions[1].units);

        vm.stopPrank();
    }

    function testCannotRebalanceComplete_NotAuthorized() public {
        vm.prank(users[1]);
        vm.expectRevert("SliceToken: Only SliceCore can call");
        // try to call rebalance from non registered address
        token.rebalanceComplete(bytes32(0));
    }

    function testCannotRebalanceComplete_InvalidRebalanceID() public {
        vm.prank(dev);
        vm.expectRevert("SliceToken: Invalid rebalance ID");
        token.rebalanceComplete(bytes32(0));
    }

    /* =========================================================== */
    /*    ===================    redeem    ====================    */
    /* =========================================================== */
    function testRedeem() public {
        vm.startPrank(dev);
        token.mint(1, maxEstimatedPrices, routes);
        bytes32 redeemId = token.redeem(1);
        assertNotEq(bytes32(0), redeemId);
        vm.stopPrank();
    }

    function testCannotRedeem_InsufficientBalance() public {
        vm.expectRevert("SliceToken: Trying to redeem more than token balance");
        token.redeem(1);
    }

    function testCannotTransfer_AmountLocked() public {
        
    }

    /* =========================================================== */
    /*   ================    redeemComplete   =================    */
    /* =========================================================== */
    function testRedeemComplete() public {
        // mint some slice tokens
        vm.startPrank(dev);

        SliceCoreMock coreMock = new SliceCoreMock(usdc, weth, wbtc, link);

        deal(address(weth), address(coreMock), wethUnits * 2);
        deal(address(wbtc), address(coreMock), wbtcUnits * 2);
        deal(address(link), address(coreMock), linkUnits * 2);

        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), address(coreMock));

        coreMock.setToken(address(sliceToken));

        sliceToken.mint(2, maxEstimatedPrices, routes);

        // call redeem underlying
        bytes32 redeemId = sliceToken.redeem(2);

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceRedeemed(dev, 2);

        coreMock.redeemComplete(redeemId, address(sliceToken));

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);

        uint256 wethTokenbalance = weth.balanceOf(address(sliceToken));
        uint256 wbtcTokenbalance = wbtc.balanceOf(address(sliceToken));
        assertEq(0, wethTokenbalance);
        assertEq(0, wbtcTokenbalance);

        uint256 sliceBalance = sliceToken.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function testCannotRedeemComplete_NotAuthorized() public {
        vm.expectRevert("SliceToken: Only Slice Core can call");
        token.redeemComplete(bytes32(0));
    }

    function testCannotRedeemComplete_InvalidRedeemID() public {
        vm.startPrank(dev);
        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, address(usdc), dev);
        vm.expectRevert("SliceToken: Invalid redeem ID");
        sliceToken.redeemComplete(bytes32(0));
        vm.stopPrank();
    }
}
