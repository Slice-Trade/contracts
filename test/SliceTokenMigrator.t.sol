// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import {CommonUtils} from "./helpers/CommonUtils.sol";
import {TokenAmountUtils} from "../src/libs/TokenAmountUtils.sol";
import {SliceTokenMigrator} from "../src/SliceTokenMigrator/SliceTokenMigrator.sol";
import {SliceCore} from "../src/SliceCore.sol";
import {SliceToken} from "../src/SliceToken.sol";
import {ISliceCore2} from "../src/SliceTokenMigrator/ISliceTokenMigrator.sol";
import {Position} from "../src/Structs.sol";
import {ChainInfo} from "../src/utils/ChainInfo.sol";
import {CrossChainPositionCreator} from "./helpers/CrossChainPositionCreator.sol";

contract SliceTokenMigratorTest is CommonUtils {
    using TokenAmountUtils for SliceTokenMigratorTest;

    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720

    SliceTokenMigrator migrator;

    SliceCore core;
    SliceToken sliceToken;
    SliceToken ccToken;

    IERC20 public usdc;

    IERC20 public wmaticPolygon;

    uint256 wmaticUnits = 95000000000000000000; // 95 wmatic

    Position[] public positions;
    Position[] public ccPositions;

    CrossChainPositionCreator public ccPosCreator;

    address public polyCore;

    address polygonLink = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;

    function setUp() public {
        vm.startPrank(dev);
        forkMainnet(MAINNET_BLOCK_NUMBER);
        forkPolygon(POLYGON_BLOCK_NUMBER);
        selectMainnet();

        usdc = IERC20(getAddress("mainnet.usdc"));

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        fillPositions(positions);

        (address sCore, address sToken,) = deployTestContracts(ChainSelect.MAINNET, "", positions);
        core = SliceCore(payable(sCore));
        sliceToken = SliceToken(payable(sToken));

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions.push(ccPos);
        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);
        ccToken = SliceToken(ccTokenAddr);

        // deploy slice token migrator
        migrator = new SliceTokenMigrator(ISliceCore2(sCore), core.chainInfo(), getAddress("mainnet.layerZeroEndpoint"), dev);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ====================  migrateStep1  ===================   */
    /* =========================================================== */
    function test_migrateStep1() public {
        
    }

    function test_cannot_migrateStep1_notRegisteredSliceToken_srcAsset() public {}

    function test_cannot_migrateStep1_notRegisteredSliceToken_dstAsset() public {}

    function test_cannot_migrateStep1_srcAssetTransferFailed() public {}

    function test_cannot_migrateStep1_srcAssetRedeemFailed() public {}

    /* =========================================================== */
    /*   ====================  migrateStep2  ===================   */
    /* =========================================================== */
    function test_migrateStep2() public {}

    function test_cannot_migrateStep2_unauthorized() public {}

    function test_cannot_migrateStep2_InvalidTransactionState() public {}

    function test_cannot_migrateStep2_AlreadyExecuted() public {}

    function test_cannot_migrateStep2_sliceMintFailed() public {}

    /* =========================================================== */
    /*   ================  withdrawMintedSlice  ================   */
    /* =========================================================== */
    function test_withdrawMintedSlice() public {}

    function test_cannot_withrawMintedSlice_Unauthorized() public {}

    function test_cannot_withdrawMintedSlice_InvalidTransactionState() public {}

    function test_cannot_withrawMintedSlice_ActionAlreadyExecuted() public {}

    /* =========================================================== */
    /*   ===============  withdrawLeftoverAssets  ==============   */
    /* =========================================================== */
    function test_withdrawLeftoverAssets() public {}

    function test_withdrawLeftoverAssets_crossChain() public {}

    function test_cannot_withdrawLeftoverAssets_Unauthorized() public {}

    function test_cannot_withdrawLeftoverAssets_InvalidTransactionState() public {}

    function test_cannot_withdrawLeftoverAssets_ActionAlreadyExecuted() public {}

    /* =========================================================== */
    /*   ===============  withrawRedeemedAssets  ===============   */
    /* =========================================================== */
    function test_withrawRedeemedAssets() public {}
    function test_withrawRedeemedAssets_crossChain() public {}
    function test_cannot_withrawRedeemedAssets_Unauthorized() public {}
    function test_cannot_withrawRedeemedAssets_InvalidTransactionState() public {}
    function test_cannot_withrawRedeemedAssets_ActionAlreadyExecuted() public {}

    /* =========================================================== */
    /*   =======================  refund  ======================   */
    /* =========================================================== */
    function test_refund() public {}

    function test_cannot_refund_Unauthorized() public {}
    function test_cannot_refund_InvalidTransactionState() public {}
    function test_cannot_refund_ActionAlreadyExecuted() public {}

    function test_cannot_refund_notEnoughMsgValue() public {}

    /* =========================================================== */
    /*   ===================  withdrawRefund  ==================   */
    /* =========================================================== */
    function test_withdrawRefund() public {}

    function test_withdrawRefund_crossChain() public {}

    function test_cannot_withdrawRefund_Unauthorized() public {}

    function test_cannot_withdrawRefund_InvalidTransactionState() public {}

    function test_cannot_withdrawRefund_ActionAlreadyExecuted() public {}

    /* =========================================================== */
    /*   ====================  withdrawDust  ===================   */
    /* =========================================================== */
    function test_withrawDust() public {}

    function test_cannot_withdrawDust_NotOwner() public {}
}
