// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

contract SliceTokenTest is Helper {
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

        usdc.approve(address(core), MAX_ESTIMATED_PRICE * 10);

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
        token.mint(2, MAX_ESTIMATED_PRICE * 2);

        // check that mint ID is properly recorded
        bytes32 mintId = token.getMintId(0);
        assertNotEq(bytes32(0), mintId);

        // verify that USDC is taken from user account
        uint256 balanceAfter = usdc.balanceOf(dev);
        uint256 expectedBalance = balanceBefore - (MAX_ESTIMATED_PRICE * 2);
        assertEq(expectedBalance, balanceAfter);

        // verify that underlying assets are in the slice token
        uint256 wethBalance = weth.balanceOf(address(token));
        uint256 wbtcBalance = wbtc.balanceOf(address(token));
        uint256 linkBalance = link.balanceOf(address(token));
        assertEq(wethBalance, positions[0].units);
        assertEq(wbtcBalance, positions[1].units);
        assertEq(linkBalance, positions[2].units);

        // verify that the slice token balance of user is incremented
        uint256 sliceTokenBalance = token.balanceOf(dev);
        assertEq(1, sliceTokenBalance);
        vm.stopPrank();
    }

    function testCannotMint_NotEnoughMoney() public {
        // call mint with a USDC amount that will fail in Core contract
        vm.prank(dev);
        usdc.transfer(users[1], MAX_ESTIMATED_PRICE);

        // verify that correct revert message is emitted
        vm.startPrank(users[1]);
        vm.expectRevert("SliceToken: Insufficient payment token balance");
        token.mint(2, MAX_ESTIMATED_PRICE * 2);

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
        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, dev);
        // call mint
        sliceToken.mint(2, MAX_ESTIMATED_PRICE * 2);

        // verify that SliceMinted event emitted
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMinted(dev, 2);

        // from dev address call mintComplete on sliceToken
        bytes32 mintId = sliceToken.getMintId(0);
        token.mintComplete(mintId);

        // verify that slice token balance of user is increased
        uint256 sliceTokenBalance = sliceToken.balanceOf(dev);
        assertEq(1, sliceTokenBalance);
        vm.stopPrank();
    }

    function testCannotMintComplete_NotAuthorized() public {
        // create a new Slice token
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, dev);
        // call mint
        sliceToken.mint(2, MAX_ESTIMATED_PRICE * 2);
        vm.stopPrank();

        vm.startPrank(users[1]);
        vm.expectRevert("SliceToken: Only Slice Core can call");
        // verify that mintComplete fails from non dev address
        bytes32 mintId = sliceToken.getMintId(0);
        token.mintComplete(mintId);
        vm.stopPrank();
    }

    function testCannotMintComplete_InvalidMintID() public {
        vm.startPrank(dev);
        // create a new Slice token
        // set the core address as dev address
        SliceToken sliceToken = new SliceToken("TEST 2", "T2", positions, dev);

        // verify that mintComplete fails with invalid mint ID
        vm.expectRevert("SliceToken: Invalid mint ID");
        sliceToken.mintComplete(bytes32(0));
    }

    /* =========================================================== */
    /*    ==================    rebalance   ===================    */
    /* =========================================================== */
    function testRebalance() public {
        // mint some slice tokens

        // call rebalance from token creator address

        // verify that positions info is updated in token

        // verify that underlying positions have been bought/sold correctly
    }

    function testCannotRebalance_NotAuthorized() public {
        // try to call rebalance from non dev address

        // verify that reverts with correct msg
    }

    /* =========================================================== */
    /*  ================   rebalanceComplete   =================   */
    /* =========================================================== */
    function testRebalanceComplete() public {}

    function testCannotRebalanceComplete_NotAuthorized() public {}

    function testCannotRebalanceComplete_InvalidRebalanceID() public {}

    /* =========================================================== */
    /*    ===================    redeem    ====================    */
    /* =========================================================== */
    function testRedeem() public {}

    function testCannotRedeem_InsufficientBalance() public {}

    /* =========================================================== */
    /*   ================    redeemComplete   =================    */
    /* =========================================================== */
    function testRedeemComplete() public {}

    function testCannotRedeemComplete_NotAuthorized() public {}

    function testCannotRedeemComplete_InvalidRedeemID() public {}
}
