// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import {CommonUtils} from "./helpers/CommonUtils.sol";
import {TokenAmountUtils} from "../src/libs/TokenAmountUtils.sol";
import {SliceTokenMigrator} from "../src/SliceTokenMigrator/SliceTokenMigrator.sol";
import {ISliceTokenMigrator} from "../src/SliceTokenMigrator/ISliceTokenMigrator.sol";
import {SliceCore} from "../src/SliceCore.sol";
import {SliceToken} from "../src/SliceToken.sol";
import {ISliceCore2} from "../src/SliceTokenMigrator/ISliceTokenMigrator.sol";
import {Position} from "../src/Structs.sol";
import {ChainInfo} from "../src/utils/ChainInfo.sol";
import {CrossChainPositionCreator} from "./helpers/CrossChainPositionCreator.sol";

import {SliceTransactionInfo} from "../src/Structs.sol";
import "../src/SliceTokenMigrator/MigratorStructs.sol";

contract SliceTokenMigratorTest is CommonUtils {
    using TokenAmountUtils for SliceTokenMigratorTest;

    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720

    SliceTokenMigrator migrator;

    uint256 migrateUnits = 1 ether;

    SliceCore core;
    SliceToken sliceToken;
    SliceToken sliceToken2;
    SliceToken ccToken;

    IERC20 public usdc;

    IERC20 public wmaticPolygon;

    IERC20 public uniswap;

    uint256 public uniUnits = 3493450000000000000000; // 3493.45 UNI
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

        uniswap = IERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        fillPositions(positions);

        (address sCore, address sToken,) = deployTestContracts(ChainSelect.MAINNET, "", positions);
        core = SliceCore(payable(sCore));
        sliceToken = SliceToken(payable(sToken));

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions.push(ccPos);
        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);
        ccToken = SliceToken(ccTokenAddr);

        positions[2] = Position(1, address(uniswap), 18, uniUnits);

        sliceToken2 = SliceToken(core.createSlice("Slice token 2", "ST2", positions));

        // deploy slice token migrator
        migrator =
            new SliceTokenMigrator(ISliceCore2(sCore), core.chainInfo(), getAddress("mainnet.layerZeroEndpoint"), dev);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ====================  migrateStep1  ===================   */
    /* =========================================================== */
    function test_migrateStep1() public {
        vm.startPrank(dev);
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        uint128[] memory fees;
        sliceToken.mint(migrateUnits, fees);

        // mint src slice
        uint256 sliceBalance = sliceToken.balanceOf(dev);
        assertEq(migrateUnits, sliceBalance);

        // approve migrator to transfer src slice
        sliceToken.approve(address(migrator), migrateUnits);

        // check that event is emitted
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;
        vm.expectEmit(true, false, false, false);
        emit ISliceTokenMigrator.MigrateStep1(expectedMigrationId);

        // call migrateStep1
        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);

        positions[2] = Position(1, address(link), 18, linkUnits);

        for (uint256 i = 0; i < positions.length; i++) {
            uint256 migratorRedeemedAssetBalance = IERC20(positions[i].token).balanceOf(address(migrator));
            assertEq(migratorRedeemedAssetBalance, positions[i].units);
        }

        positions[2] = Position(1, address(uniswap), 18, uniUnits);

        // check that slice core has been approved to spend the dst asset
        for (uint256 i = 0; i < positions.length; i++) {
            uint256 allowance = IERC20(positions[i].token).allowance(address(migrator), address(core));
            assertEq(allowance, positions[i].units);
        }

        // check migration info
        (bytes32 id, bytes32 redeemId,, address creator,,, uint256 fromAmount, uint256 mintAmount) =
            migrator.migrationInfos(expectedMigrationId);
        assertEq(id, expectedMigrationId);
        assertEq(creator, dev);
        assertEq(fromAmount, migrateUnits);
        assertEq(mintAmount, migrateUnits);

        SliceTransactionInfo memory redeemInfo = sliceToken.getRedeem(redeemId);
        // redeem fulfilled
        assertEq(uint256(redeemInfo.state), 2);
    }

    function test_migrateStep1_crossChain() public {
        // TODO
    }

    function test_cannot_migrateStep1_notRegisteredSliceToken_srcAsset() public {
        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        migrator.migrateStep1(address(1), address(sliceToken2), migrateUnits, fees);
    }

    function test_cannot_migrateStep1_notRegisteredSliceToken_dstAsset() public {
        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        migrator.migrateStep1(address(sliceToken), address(1), migrateUnits, fees);
    }

    function test_cannot_migrateStep1_srcAssetTransferFailed() public {
        // user doesnt have the slice
        uint128[] memory fees;

        vm.expectRevert();
        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);

        vm.startPrank(dev);
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        sliceToken.mint(migrateUnits, fees);
        // missing approval
        vm.expectRevert();
        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);
    }

    function test_cannot_migrateStep1_noAssetsInCommon() public {
        vm.startPrank(dev);
        deal(address(ccToken), address(dev), wethUnits);
        deal(dev, 10 ether);

        ccToken.approve(address(migrator), migrateUnits);

        uint128[] memory fees = new uint128[](1);
        fees[0] = 1 ether;
        vm.expectRevert(bytes4(keccak256("NoAssetsInCommon()")));
        migrator.migrateStep1{value: 1.5 ether}(address(ccToken), address(sliceToken2), migrateUnits, fees);
    }

    function test_cannot_migrateStep1_crossChain_srcAssetRedeemFailed() public {
        // TODO
    }

    /* =========================================================== */
    /*   ====================  migrateStep2  ===================   */
    /* =========================================================== */
    function test_migrateStep2() public {
        vm.startPrank(dev);
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        uint128[] memory fees;
        sliceToken.mint(migrateUnits, fees);

        sliceToken.approve(address(migrator), migrateUnits);

        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);

        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        (bytes32 id,, bytes32 mintId, address creator,,, uint256 fromAmount, uint256 mintAmount) =
            migrator.migrationInfos(expectedMigrationId);

        assertEq(id, expectedMigrationId);
        assertEq(creator, dev);
        assertEq(fromAmount, migrateUnits);
        assertEq(mintAmount, migrateUnits);

        SliceTransactionInfo memory mintInfo = sliceToken2.getMint(mintId);
        assertEq(uint256(mintInfo.state), 2);

        uint256 migratorBalance = sliceToken2.balanceOf(address(migrator));
        assertEq(migratorBalance, migrateUnits);
        vm.stopPrank();
    }

    function test_cannot_migrateStep2_unauthorized() public {
        vm.startPrank(dev);
        deal(address(weth), address(dev), wethUnits);
        deal(address(wbtc), address(dev), wbtcUnits);
        deal(address(link), address(dev), linkUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        uint128[] memory fees;
        sliceToken.mint(migrateUnits, fees);

        sliceToken.approve(address(migrator), migrateUnits);

        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);

        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        migrator.migrateStep2(expectedMigrationId, fees);
        vm.stopPrank();
    }

    function test_cannot_migrateStep2_InvalidTransactionState() public {
        vm.startPrank(dev);
        deal(dev, 10 ether);
        deal(address(weth), address(core), wethUnits);

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions[0] = Position(1, address(weth), 18, wethUnits);
        ccPositions.push(ccPos);

        address newSliceToken = core.createSlice("new cc token", "ncc", ccPositions);
        ccToken = SliceToken(newSliceToken);
        deal(address(ccToken), address(dev), wethUnits);

        ccToken.approve(address(migrator), migrateUnits);

        uint128[] memory fees = new uint128[](1);
        fees[0] = 1 ether;
        migrator.migrateStep1{value: 1.5 ether}(address(ccToken), address(sliceToken2), migrateUnits, fees);

        bytes32 migrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));
        migrator.migrateStep2(migrationId, fees);
        vm.stopPrank();
    }

    function test_cannot_migrateStep2_AlreadyExecuted() public {
        vm.startPrank(dev);
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);
        wbtc.approve(address(core), wbtcUnits);

        uint128[] memory fees;
        sliceToken.mint(migrateUnits, fees);

        sliceToken.approve(address(migrator), migrateUnits);

        migrator.migrateStep1(address(sliceToken), address(sliceToken2), migrateUnits, fees);

        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        vm.expectRevert(abi.encodeWithSelector(ISliceTokenMigrator.ActionAlreadyExecuted.selector, "migrateStep2"));

        migrator.migrateStep2(expectedMigrationId, fees);
        vm.stopPrank();
    }

    function test_cannot_migrateStep2_sliceMintFailed() public {
        // TODO
        // cross-chain migrate, should fail when no msg.value sent to migrateStep2
    }

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
    function test_withrawDust() public {
        deal(address(migrator), 0.1 ether);
        vm.prank(dev);
        migrator.withdrawDust(users[1]);
        uint256 uBalance = address(users[1]).balance;
        assertEq(uBalance, 0.1 ether);
    }

    function test_cannot_withdrawDust_NotOwner() public {
        vm.expectRevert();
        migrator.withdrawDust(users[1]);
    }
}
