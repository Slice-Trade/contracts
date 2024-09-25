// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

contract SliceTokenMigratorTest is Helper {
    function setUp() public {

    }

    /* =========================================================== */
    /*   ====================  migrateStep1  ===================   */
    /* =========================================================== */
    function test_migrateStep1() public {

    }

    function test_cannot_migrateStep1_notRegisteredSliceToken_srcAsset() public {
    
    }

    function test_cannot_migrateStep1_notRegisteredSliceToken_dstAsset() public {

    }

    function test_cannot_migrateStep1_srcAssetTransferFailed() public {

    }

    function test_cannot_migrateStep1_srcAssetRedeemFailed() public {

    }

    /* =========================================================== */
    /*   ====================  migrateStep2  ===================   */
    /* =========================================================== */
    function test_migrateStep2() public {

    }

    function test_cannot_migrateStep2_unauthorized() public {

    }

    function test_cannot_migrateStep2_InvalidTransactionState() public {

    }

    function test_cannot_migrateStep2_AlreadyExecuted() public {

    }

    function test_cannot_migrateStep2_sliceMintFailed() public {

    }

    /* =========================================================== */
    /*   ================  withdrawMintedSlice  ================   */
    /* =========================================================== */
    function test_withdrawMintedSlice() public {

    }

    function test_cannot_withrawMintedSlice_Unauthorized() public {

    }

    function test_cannot_withdrawMintedSlice_InvalidTransactionState() public {

    }

    function test_cannot_withrawMintedSlice_ActionAlreadyExecuted() public {

    }

    /* =========================================================== */
    /*   ===============  withdrawLeftoverAssets  ==============   */
    /* =========================================================== */
    function test_withdrawLeftoverAssets() public {

    }

    function test_withdrawLeftoverAssets_crossChain() public {

    }

    function test_cannot_withdrawLeftoverAssets_Unauthorized() public {

    }

    function test_cannot_withdrawLeftoverAssets_InvalidTransactionState() public {

    }

    function test_cannot_withdrawLeftoverAssets_ActionAlreadyExecuted() public {

    }

    /* =========================================================== */
    /*   ===============  withrawRedeemedAssets  ===============   */
    /* =========================================================== */
    function test_withrawRedeemedAssets() public {

    }
    function test_withrawRedeemedAssets_crossChain() public {

    }
    function test_cannot_withrawRedeemedAssets_Unauthorized() public {

    }
    function test_cannot_withrawRedeemedAssets_InvalidTransactionState() public {

    }
    function test_cannot_withrawRedeemedAssets_ActionAlreadyExecuted() public {

    }

    /* =========================================================== */
    /*   =======================  refund  ======================   */
    /* =========================================================== */
    function test_refund() public {

    }

    function test_cannot_refund_Unauthorized() public {
        
    }
    function test_cannot_refund_InvalidTransactionState() public {

    }
    function test_cannot_refund_ActionAlreadyExecuted() public {

    }

    function test_cannot_refund_notEnoughMsgValue() public {

    }

    /* =========================================================== */
    /*   ===================  withdrawRefund  ==================   */
    /* =========================================================== */
    function test_withdrawRefund() public {

    }

    function test_withdrawRefund_crossChain() public {

    }

    function test_cannot_withdrawRefund_Unauthorized() public {

    }

    function test_cannot_withdrawRefund_InvalidTransactionState() public {

    }

    function test_cannot_withdrawRefund_ActionAlreadyExecuted() public {

    }

    /* =========================================================== */
    /*   ====================  withdrawDust  ===================   */
    /* =========================================================== */
    function test_withrawDust() public {

    }

    function test_cannot_withdrawDust_NotOwner() public {
        
    }
}