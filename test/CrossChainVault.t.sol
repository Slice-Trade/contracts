// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

import {ICrossChainVault} from "../src/CrossChainVault/ICrossChainVault.sol";

contract CrossChainVaultTest is Helper {
    ICrossChainVault vault;

    /* =========================================================== */
    /*   ======================    setup   ====================    */
    /* =========================================================== */
    function setUp() public {}

    /* =========================================================== */
    /*   ==============  createCommitmentStrategy  =============   */
    /* =========================================================== */
    function test_createCommitmentStrategy() public {}

    function test_cannot_createCommitmentStrategy_notRegisteredSliceToken() public {}

    function test_cannot_createCommitmentStrategy_invalidTarget() public {}

    /* =========================================================== */
    /*  ===========  modfifyCommitmentStrategyTarget  ===========  */
    /* =========================================================== */
    function test_modifyCommitmentStrategyTarget() public {}

    function test_cannot_modifyCommitmentStrategyTarget_NotStrategyCreator() public {}

    function test_cannot_modifyCommitmentStrategyTarget_InvalidStrategyId() public {}

    function test_cannot_modifyCommitmentStrategyTarget_InvalidTarget() public {}

    function test_cannot_modifyCommitmentStrategyTarget_InvalidState() public {}

    /* =========================================================== */
    /*  ==============  executeCommitmentStrategy  =============   */
    /* =========================================================== */
    function test_executeCommitmentStrategy() public {}

    function test_cannot_executeCommitmentStrategy_TargetNotReached() public {}

    function test_cannot_executeCommitmentStrategy_InvalidState() public {}

    function test_cannot_executeCommitmentStrategy_OraclePriceStale() public {}

    function test_cannot_executeCommitmentStrategy_InsufficientLzFee() public {}

    /* =========================================================== */
    /*  ===================  commitToStrategy  =================   */
    /* =========================================================== */
    function test_commitToStrategy() public {}

    function test_commitToStrategy_TooMuchInCappedAtMax() public {}

    function test_cannot_commitToStrategy_InvalidStrategyId() public {}

    function test_cannot_commitToStrategy_InvalidStrategyState() public {}

    function test_cannot_commitToStrategy_UnapprovedUser() public {}

    function test_cannot_commitToStrategy_InvalidAsset() public {}

    function test_cannot_commitToStrategy_InsufficientAmountBalance() public {}

    function test_cannot_commitToStrategy_MissingApproval() public {}

    function test_cannot_commitToStrategy_InsufficientFeeForCrossChainCommit() public {}

    /* =========================================================== */
    /*  ============  removeCommitmentFromStrategy  =============  */
    /* =========================================================== */
    function test_removeCommitmentFromStrategy() public {}

    function test_cannot_removeCommitmentFromStrategy_InvalidCommitmentId() public {}

    function test_cannot_removeCommitmentFromStrategy_NotCommitmentCreator() public {}

    function test_cannot_removeCommitmentFromStrategy_InvalidAmount() public {}

    function test_cannot_removeCommitmentFromStrategy_InvalidStrategyState() public {}

    function test_cannot_removeCommitmentFromStrategy_InsufficientFeesForCrossChainRemoval() public {}

    /* =========================================================== */
    /*  ================  pullMintedTokenShares  ================  */
    /* =========================================================== */
    function test_pullMintedTokenShares() public {}

    function test_cannot_pullMintedTokenShares_UnauthorizedUser() public {}

    function test_cannot_pullMintedTokenShares_InvalidStrategyId() public {}

    function test_cannot_pullMintedTokenShares_InvalidStrategyState() public {}

    function test_cannot_pullMintedTokenShares_AlreadyPulled() public {}

    /* =========================================================== */
    /*  =============  updateUnderlyingAssetPrices  =============  */
    /* =========================================================== */
    function test_updateUnderlyingAssetPrices() public {}

    function test_cannot_updateUnderlyingAssetPrices_InvalidStrategyId() public {}

    /* =========================================================== */
    /* ========== changeUserApprovalToCommitmentStrategy ========= */
    /* =========================================================== */
    function test_changeUserApprovalToCommitmentStrategy() public {}

    function test_cannot_changeUserApprovalToCommitmentStrategy_NotStrategyCreator() public {}

    function test_cannot_changeUserApprovalToCommitmentStrategy_InvalidStrategyId() public {}

    function test_cannot_changeUserApprovalToCommitmentStrategy_NotPrivateStrategy() public {}

    function test_cannot_changeUserApprovalToCommitmentStrategy_InvalidStrategyState() public {}

    /* =========================================================== */
    /*  ======================  pauseVault  =====================  */
    /* =========================================================== */
    function test_pauseVault() public {}

    function test_cannot_pauseVault_NotAdmin() public {}

    function test_cannot_pauseVault_AlreadyPaused() public {}

    /* =========================================================== */
    /*  ====================  restartVault  =====================  */
    /* =========================================================== */
    function test_restartVault() public {}

    function test_cannot_restartVault_NotAdmin() public {}

    function test_cannot_restartVault_NotPaused() public {}
}
