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

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet();

        usdc = IERC20(constants.getAddress("mainnet.usdc"));
        weth = IWETH(constants.getAddress("mainnet.weth"));
        wbtc = IERC20(constants.getAddress("mainnet.wbtc"));
        link = IERC20(constants.getAddress("mainnet.link"));

        vm.startPrank(dev);

        core = new SliceCore();
        token = new SliceToken("Slice Token", "SC");

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function testCreateSlice() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(users[1], true);

        // create positions       
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            100000000000000000 // 0.1 wETH
        );

        Position memory wbtcPosition = Position(
            1, // mainnet
            address(wbtc), // wrapped BTC
            10000000000000000 // 0.01 wBTC
        );

        Position memory linkPosition = Position(
            1, // mainnet
            address(link), // chainlink
            20000000000000000000 // 20 LINK
        );

        positions.push(wethPosition);
        positions.push(wbtcPosition);
        positions.push(linkPosition);


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

    /* =========================================================== */
    /*   ===========   purchaseUnderlyingAssets   =============    */
    /* =========================================================== */
    function testPurchaseUnderlyingAssets() public {
        // create a mock Slice token 

        // call mint -> call purchase underlying assets

        // verify that the assets are purhased

        // verify that event is emitted

    }

    function testCannotPurchaseUnderlyingAssets_NotRegistedSliceToken() public {
        // call purchaseUnderlying from a non-registered address

        // verify that it reverts with the correct revert msg
    }

    function testCannotPurchaseUnderlyingAssets_NotEnoughMoney() public {
        // call purchase underlying from address with no payment token

        // verify that it reverts with the correct revert msg
    }

    /* =========================================================== */
    /*   =============    rebalanceUnderlying   ===============    */
    /* =========================================================== */
    function testRebalanceUnderlying() public {

    }

    function testCannotRebalanceUnderlying_NotAuthorized() public {

    }

    function testCannotRebalanceUnderlying_InvalidUnits() public {

    }

    /* =========================================================== */
    /*   =============    rebalanceUnderlying   ===============    */
    /* =========================================================== */
    function testRedeemUnderlying() public {

    }

    function testCannotRedeemUnderlying_NotAuthorized() public {

    }

    /* =========================================================== */
    /*  =========   changeSliceTokenCreationEnabled   ===========  */
    /* =========================================================== */
    function testChangeSliceTokenCreationEnabled() public {

    }

    function testCannotChangeSliceTokenCreationEnabled_NotAuthorized() public {

    }
}