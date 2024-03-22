// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

contract SliceCoreTest is Helper {
    SliceCore core;
    SliceToken token;

    IERC20 public usdc;

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        forkMainnet();

        usdc = IERC20(constants.getAddress("mainnet.usdc"));

        vm.startPrank(dev);

        core = new SliceCore();
        token = new SliceToken("Slice Token", "SC");

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);
    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function testCreateSlice() public {
        // approve address as Slice token creator

        // call create Slice token from that address

        // verify that the Slice token is deployed

        // verify that Slice token works

        // verify that Slice token address is registered in the core contract

        // verify that create Slice event emitted
    }

    function testCannotCreateSlice_NotAuthorized() public {
        // call create Slice token from an unverified address

        // verify that transaction fails with the correct revert message
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