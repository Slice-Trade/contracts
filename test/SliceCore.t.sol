// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/ChainInfo.sol";

import "../src/interfaces/ISliceCoreErrors.sol";
import "../src/SliceCore.sol";
import "../src/SliceToken.sol";
import "../src/libs/SliceTokenDeployer.sol";

contract SliceCoreTest is Helper {
    uint256 immutable BLOCK_NUMBER = 19518913;
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
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001";
    bytes public usdcWbtcRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001CEfF51756c56CeFFCA006cD410B03FFC46dd3a5804C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200CEfF51756c56CeFFCA006cD410B03FFC46dd3a5800";
    bytes public usdcLinkRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001C40D16476380e4037e6b1A2594cAF6a6cc8Da96704C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200C40D16476380e4037e6b1A2594cAF6a6cc8Da96700";

    
    /* CROSS_CHAIN */
    uint256 maxWMaticPrice = 100000000; //100usdc
    uint256 wmaticUnits = 95000000000000000000; // 95matic

    uint256[] public maxEstCCPrices;
    Position[] public ccPositions;
    bytes[] public ccRoutes;
    bytes public usdcWmaticRoute = hex"012791Bca1f2de4661ED88A30C99A7a9449Aa8417402555500cd353F79d9FADe311fC3119B841e1f456b54e85800eeb3e0999D01f0d1Ed465513E414725a357F6ae4ffff0121988C9CFD08db3b5793c2C6782271dC9474925100";
    
    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet(BLOCK_NUMBER);

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

        ChainInfo chainInfo = new ChainInfo();

        SliceTokenDeployer deployer = new SliceTokenDeployer(); 

        core = new SliceCore(
            address(usdc),
            getAddress("mainnet.sushiXSwap"),
            getAddress("mainnet.stargateAdapter"),
            getAddress("mainnet.axelarAdapter"),
            getAddress("mainnet.layerZeroEndpoint"), // TODO
            address(chainInfo),
            address(deployer),
            dev
        );
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(dev, true);

        usdcWethRoute = abi.encodePacked(usdcWethRoute, address(core));
        usdcWbtcRoute = abi.encodePacked(usdcWbtcRoute, address(core));
        usdcLinkRoute = abi.encodePacked(usdcLinkRoute, address(core));
        usdcWmaticRoute = abi.encodePacked(usdcWmaticRoute, address(core));

        routes.push(usdcWethRoute);
        routes.push(usdcWbtcRoute);
        routes.push(usdcLinkRoute);

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
    /*   ===========   purchaseUnderlyingAssets   =============    */
    /* =========================================================== */
    function test_PurchaseUnderlyingAssets() public {
        vm.startPrank(dev);
        // call mint -> call purchase underlying assets

        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsPurchased(address(token), 1000000000000000000, dev);

        token.mint(1000000000000000000, maxEstimatedPrices, routes);

        // verify that the assets are purhased
        uint256 wethBalance = weth.balanceOf(address(core));
        uint256 wbtcBalance = wbtc.balanceOf(address(core));
        uint256 linkBalance = link.balanceOf(address(core));

        assertGe(wethBalance, wethUnits);
        assertGe(wbtcBalance, wbtcUnits);
        assertGe(linkBalance, linkUnits);

        vm.stopPrank();
    }

    function test_PurchaseUnderlyingAssets_CrossChain() public {
        vm.startPrank(dev);

        vm.deal(dev, 100 ether);

        (bool success, ) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        bytes32 mintID = ccToken.mint(1000000000000000000, maxEstCCPrices, ccRoutes);

        SlicePayloadData memory pd = SlicePayloadData(
            137,
            mintID,
            address(weth),
            10000000000000000000,
            ""
        );

        bytes memory pd_enc = abi.encode(pd);

        deal(address(weth), address(core), 10000000000000000000);

        core.setPeer(30109, bytes32(uint256(uint160(address(core)))));

        vm.stopPrank();

        vm.prank(getAddress("mainnet.stargateAdapter"));

        core.onPayloadReceive(pd_enc);

        // forkPolygon(BLOCK_NUMBER);


        // make contract persistent
/*         makePersistent(address(core));
        makePersistent(address(ccToken));

        // change network 
        forkOptimism(BLOCK_NUMBER); */
        // transfer tokens to SliceCore crosschain contract

        vm.stopPrank();
    }

    function test_Cannot_PurchaseUnderlyingAssets_NotRegistedSliceToken() public {
        // verify that it reverts with the correct revert msg
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        // call purchaseUnderlying from a non-registered address
        core.purchaseUnderlyingAssets(bytes32(0), 1, maxEstimatedPrices, routes);
    }

    // TODO: cannot purchase - invalid mint id

    /* =========================================================== */
    /*   ==============    redeemUnderlying    ================    */
    /* =========================================================== */
    function test_RedeemUnderlying() public {
        // mint some slice tokens
        vm.startPrank(dev);
        
        token.mint(1000000000000000000, maxEstimatedPrices, routes);
        uint256 wethTokenbalanceBefore = weth.balanceOf(address(core));
        uint256 wbtcTokenbalanceBefore = wbtc.balanceOf(address(core));
        uint256 linkTokenbalanceBefore = link.balanceOf(address(core));
        // call redeem underlying
        token.redeem(1000000000000000000);

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        uint256 linkBalance = link.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);
        assertEq(linkBalance, positions[2].units);

        uint256 wethTokenbalance = weth.balanceOf(address(core));
        uint256 wbtcTokenbalance = wbtc.balanceOf(address(core));
        uint256 linkTokenbalance = link.balanceOf(address(core));

        assertEq(wethTokenbalanceBefore - wethTokenbalance, wethUnits);
        assertEq(wbtcTokenbalanceBefore - wbtcTokenbalance, wbtcUnits);
        assertEq(linkTokenbalanceBefore - linkTokenbalance, linkUnits);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function test_Cannot_RedeemUnderlying_NotAuthorized() public {
        // verify that it reverts with the correct reason
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        // call redeem from not registered slice token
        core.redeemUnderlying(bytes32(0));
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
    /*   =============    rebalanceUnderlying   ===============    */
    /* =========================================================== */
/*     function testRebalanceUnderlying() public {
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
        uint256 wethBalance = weth.balanceOf(address(core));
        uint256 wbtcBalance = wbtc.balanceOf(address(core));
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
    } */
}