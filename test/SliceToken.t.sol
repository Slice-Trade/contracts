// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/src/Test.sol";
import "./helpers/Helper.sol";

import "../src/SliceCore.sol";
import "../src/SliceToken.sol";

contract SliceTokenTest is Helper {
    SliceCore core;
    SliceToken token;

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */
    function setUp() public {
        // fork mainnet
        forkMainnet();
        
        vm.startPrank(dev);

        core = new SliceCore();
        token = new SliceToken("Slice Token", "SC");
    }

    /* =========================================================== */
    /*    ==================      mint     ====================    */
    /* =========================================================== */
    function testMint() public {

    }

    function testCannotMint_NotEnoughMoney() public {

    }

    /* =========================================================== */
    /*   =================    mintComplete   ==================    */
    /* =========================================================== */
    function testMintComplete() public {

    }

    function testCannotMintComplete_NotAuthorized() public {

    }

    function testCannotMintComplete_InvalidMintID() public {

    }

    /* =========================================================== */
    /*    ==================    rebalance   ===================    */
    /* =========================================================== */
    function testRebalance() public {

    }

    function testCannotRebalance_NotAuthorized() public {

    }

    /* =========================================================== */
    /*  ================   rebalanceComplete   =================   */
    /* =========================================================== */
    function testRebalanceComplete() public {

    }

    function testCannotRebalanceComplete_NotAuthorized() public {

    }

    function testCannotRebalanceComplete_InvalidRebalanceID() public {

    }

    /* =========================================================== */
    /*    ===================    redeem    ====================    */
    /* =========================================================== */
    function testRedeem() public {

    }

    function testCannotRedeem_InsufficientBalance() public {

    }

    /* =========================================================== */
    /*   ================    redeemComplete   =================    */
    /* =========================================================== */
    function testRedeemComplete() public {

    }

    function testCannotRedeemComplete_NotAuthorized() public {

    }

    function testCannotRedeemComplete_InvalidRedeemID() public {

    }
}