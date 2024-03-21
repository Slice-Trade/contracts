// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

contract SliceCoreTest is Test, Helper {
    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {

    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function testCreateSlice() public {

    }

    function testCannotCreateSlice_NotAuthorized() public {

    }

    /* =========================================================== */
    /*   ===========   purchaseUnderlyingAssets   =============    */
    /* =========================================================== */
    function testPurchaseUnderlyingAssets() public {

    }

    function testCannotPurchaseUnderlyingAssets_NotRegistedSliceToken() public {

    }

    function testCannotPurchaseUnderlyingAssets_NotEnoughMoney() public {
        
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