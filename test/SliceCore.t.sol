// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

contract SliceCoreTest is Helper {
    SliceCore core;
    SliceToken token;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public wbtc;
    IERC20 public link;

    Position[] public positions;

    uint256 constant MAX_ESTIMATED_PRICE = 1355000000; // 1355 USDC

    uint256 public wethUnits = 100000000000000000; // 0.1 wETH
    uint256 public wbtcUnits = 10000000000000000; // 0.01 wBTC
    uint256 public linkUnits = 20000000000000000000; // 20 LINK

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet();

        usdc = IERC20(constants.getAddress("mainnet.usdc"));
        weth = IWETH(constants.getAddress("mainnet.weth"));
        wbtc = IERC20(constants.getAddress("mainnet.wbtc"));
        link = IERC20(constants.getAddress("mainnet.link"));

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);

        vm.startPrank(dev);

        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(dev, true);

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

        core = new SliceCore();
        address tokenAddr = core.createSlice("Slice Token", "SC", positions);
        token = SliceToken(tokenAddr);

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
        // verify that create Slice event emitted
        vm.expectEmit(true, false, false, false);
        emit ISliceCore.SliceTokenCreated(address(0)); // TODO

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
        emit ISliceCore.UnderlyingAssetsPurchased(address(token), 1, dev);

        token.mint(1, MAX_ESTIMATED_PRICE);

        // verify that the assets are purhased
        uint256 wethBalance = weth.balanceOf(address(token));
        uint256 wbtcBalance = wbtc.balanceOf(address(token));
        uint256 linkBalance = link.balanceOf(address(token));

        assertEq(wethUnits, wethBalance);
        assertEq(wbtcUnits, wbtcBalance);
        assertEq(linkUnits, linkBalance);
        vm.stopPrank();
    }

    function testPurchaseUnderlyingAssets_Multichain() public {
        // TODO
    }

    function testCannotPurchaseUnderlyingAssets_NotRegistedSliceToken() public {
        // verify that it reverts with the correct revert msg
        vm.expectRevert("SliceCore: Only registered Slice token can call");
        // call purchaseUnderlying from a non-registered address
        core.purchaseUnderlyingAssets(bytes32(0), 1, 1 ether);
    }

    function testCannotPurchaseUnderlyingAssets_NotEnoughMoney() public {
        // call purchase underlying with wrong expected amount
        vm.prank(dev);
        // verify that it reverts with the correct revert msg
        vm.expectRevert("SliceCore: Max estimated price lower than required");
        token.mint(1, 1000000);
    }

    /* =========================================================== */
    /*   =============    rebalanceUnderlying   ===============    */
    /* =========================================================== */
    function testRebalanceUnderlying() public {
        // mint some tokens
        vm.startPrank(dev);
        token.mint(2, MAX_ESTIMATED_PRICE * 2);

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
        token.mint(2, MAX_ESTIMATED_PRICE * 2);

        // call redeem underlying
        token.redeem(2);

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 wbtcBalance = wbtc.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function testCannotRedeemUnderlying_NotAuthorized() public {
        // verify that it reverts with the correct reason
        vm.expectRevert("SliceCore: Only registered Slice token can call");
        // call redeem from not registered slice token
        core.redeemUnderlying(bytes32(0), RedeemInfo(address(0),0,address(0),bytes("")));
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

        vm.expectRevert("SliceCore: Slice token creation is disabled");
        // verify that we cannot create slice tokens 
        core.createSlice("New Test Token", "NTT", positions);
        vm.stopPrank();
    }

    function testCannotChangeSliceTokenCreationEnabled_NotAuthorized() public {
        vm.prank(users[2]);
        // verify that it reverts with the correct revert msg
        vm.expectRevert("SliceToken: Unauthorized");
        // try changing enable/disable with non-owner address
        core.changeSliceTokenCreationEnabled(false);
    }
}