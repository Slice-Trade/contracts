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
import "../src/Structs.sol";
import "../src/SliceTokenMigrator/MigratorStructs.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";
import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";

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

        (address sCore, address sToken,, address sMigrator) = deployTestContracts(ChainSelect.MAINNET, "", positions);
        core = SliceCore(payable(sCore));
        sliceToken = SliceToken(payable(sToken));
        migrator = SliceTokenMigrator(payable(sMigrator));

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions.push(ccPos);
        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);
        ccToken = SliceToken(ccTokenAddr);

        positions[2] = Position(1, address(uniswap), 18, uniUnits);

        sliceToken2 = SliceToken(core.createSlice("Slice token 2", "ST2", positions));

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
        migrateStep1CrossChain();
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

        (bool step2Executed,,,,,) = migrator.migrationActions(expectedMigrationId);
        assertTrue(step2Executed);
        vm.stopPrank();
    }

    function test_migrateStep2_crossChain() public {
        migrateStep2CrossChain();
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
        migrateStep1CrossChain();
        bytes32 expectedMigrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        uint128[] memory fees;
        // cross-chain migrate, should fail when no msg.value sent to migrateStep2
        vm.prank(dev);
        vm.expectRevert();
        migrator.migrateStep2(expectedMigrationId, fees);
    }

    /* =========================================================== */
    /*   ================  withdrawMintedSlice  ================   */
    /* =========================================================== */
    function test_withdrawMintedSlice() public {
        // do step 1
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

        // do step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        uint256 migratorSliceTokenBalanceBefore = sliceToken2.balanceOf(address(migrator));
        uint256 devSliceTokenBalanceBefore = sliceToken2.balanceOf(address(dev));

        assertEq(migratorSliceTokenBalanceBefore, migrateUnits);
        assertEq(devSliceTokenBalanceBefore, 0);
        // withdraw the minted slices
        migrator.withdrawMintedSlice(expectedMigrationId);

        uint256 migratorSliceTokenBalanceAfter = sliceToken2.balanceOf(address(migrator));
        uint256 devSliceTokenBalanceAfter = sliceToken2.balanceOf(address(dev));
        assertEq(migratorSliceTokenBalanceAfter, 0);
        assertEq(devSliceTokenBalanceAfter, migrateUnits);

        (, bool mintedSliceWithdrawn,,,,) = migrator.migrationActions(expectedMigrationId);
        assertTrue(mintedSliceWithdrawn);
    }

    function test_cannot_withrawMintedSlice_Unauthorized() public {
        // do step 1
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

        // do step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        uint256 migratorSliceTokenBalanceBefore = sliceToken2.balanceOf(address(migrator));
        uint256 devSliceTokenBalanceBefore = sliceToken2.balanceOf(address(dev));

        assertEq(migratorSliceTokenBalanceBefore, migrateUnits);
        assertEq(devSliceTokenBalanceBefore, 0);
        vm.stopPrank();
        // withdraw the minted slices
        vm.expectRevert(ISliceTokenMigrator.Unauthorized.selector);
        migrator.withdrawMintedSlice(expectedMigrationId);
    }

    function test_cannot_withdrawMintedSlice_InvalidTransactionState() public {
        // do step 1
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
        vm.expectRevert(ISliceTokenMigrator.InvalidTransactionState.selector);
        migrator.withdrawMintedSlice(expectedMigrationId);
    }

    function test_cannot_withrawMintedSlice_ActionAlreadyExecuted() public {
        // do step 1
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

        // do step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        uint256 migratorSliceTokenBalanceBefore = sliceToken2.balanceOf(address(migrator));
        uint256 devSliceTokenBalanceBefore = sliceToken2.balanceOf(address(dev));

        assertEq(migratorSliceTokenBalanceBefore, migrateUnits);
        assertEq(devSliceTokenBalanceBefore, 0);
        // withdraw the minted slices
        migrator.withdrawMintedSlice(expectedMigrationId);

        vm.expectRevert(
            abi.encodeWithSelector(ISliceTokenMigrator.ActionAlreadyExecuted.selector, "withdrawMintedSlice")
        );
        migrator.withdrawMintedSlice(expectedMigrationId);
    }

    /* =========================================================== */
    /*   ===============  withdrawLeftoverAssets  ==============   */
    /* =========================================================== */
    function test_withdrawLeftoverAssets() public {
        vm.startPrank(dev);
        // update slice token so that one of the assets is bigger in quantity than in slice token 2
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits + 10 ether
        );
        positions[0] = wethPosition;
        positions[2] = Position({chainId: 1, token: address(wbtc), decimals: 8, units: wbtcUnits});

        // create new slice token with these positions
        address newSlice = core.createSlice("Test", "T", positions);
        sliceToken = SliceToken(newSlice);
        wethUnits = wethUnits + 10 ether;

        // mint slice token
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

        bytes32 expectedMigrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);

        // do migrate into slice token 2
        migrator.migrateStep2(expectedMigrationId, fees);

        uint256 wethBalanceMigratorBefore = weth.balanceOf(address(migrator));
        assertEq(wethBalanceMigratorBefore, wethUnits - 10 ether);

        uint256 wethBalanceUserBefore = weth.balanceOf(address(dev));

        // withdraw leftover assets
        migrator.withdrawLeftoverAssets(expectedMigrationId);

        // check that the values are all correct
        uint256 wethBalanceMigratorAfter = weth.balanceOf(address(migrator));
        assertEq(wethBalanceMigratorAfter, 0);

        uint256 wethBalanceUserAfter = weth.balanceOf(address(dev));
        assertEq(wethBalanceUserAfter, wethBalanceUserBefore + 10 ether);
        vm.stopPrank();
    }

    function test_withdrawLeftoverAssets_crossChain() public {
        migrateStep2CrossChain();
        
        selectPolygon();
        uint256 leftoverMatic = wmaticPolygon.balanceOf(address(migrator));
        assertEq(leftoverMatic, 100 ether);

        selectMainnet();
        bytes32 expectedMigrationId = 0xf9b2b245d7a63560f05170c070a2d82e7ad17ee43d83b9921be81ede27716cda;
        vm.prank(dev);
        migrator.withdrawLeftoverAssets{value: 1 ether}(expectedMigrationId);

        MigratorCrossChainSignal[] memory ccsMsgs = new MigratorCrossChainSignal[](1);
        MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
            ccsType: MigratorCrossChainSignalType.WITHDRAW,
            underlying: address(wmaticPolygon),
            user: address(dev),
            amount: leftoverMatic
        });

        ccsMsgs[0] = ccs;
        bytes memory ccsEncoded = abi.encode(ccsMsgs);
        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(migrator)))), nonce: 1});
        makePersistent(address(migrator));

        selectPolygon();

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(address(migrator)).lzReceive{value: 160 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 maticBalanceAfter = wmaticPolygon.balanceOf(address(migrator));
        assertEq(maticBalanceAfter, 0);

        uint256 userMaticBalance = wmaticPolygon.balanceOf(address(dev));
        assertEq(leftoverMatic, userMaticBalance);
    }

    function test_cannot_withdrawLeftoverAssets_Unauthorized() public {
        vm.startPrank(dev);
        // update slice token so that one of the assets is bigger in quantity than in slice token 2
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits + 10 ether
        );
        positions[0] = wethPosition;
        positions[2] = Position({chainId: 1, token: address(wbtc), decimals: 8, units: wbtcUnits});

        // create new slice token with these positions
        address newSlice = core.createSlice("Test", "T", positions);
        sliceToken = SliceToken(newSlice);
        wethUnits = wethUnits + 10 ether;

        // mint slice token
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

        bytes32 expectedMigrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);

        // do migrate into slice token 2
        migrator.migrateStep2(expectedMigrationId, fees);
        vm.stopPrank();

        vm.expectRevert(ISliceTokenMigrator.Unauthorized.selector);
        migrator.withdrawLeftoverAssets(expectedMigrationId);
    }

    function test_cannot_withdrawLeftoverAssets_InvalidTransactionState() public {
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
        migrator.withdrawLeftoverAssets(migrationId);
        vm.stopPrank();
    }

    function test_cannot_withdrawLeftoverAssets_ActionAlreadyExecuted() public {
        vm.startPrank(dev);
        // update slice token so that one of the assets is bigger in quantity than in slice token 2
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits + 10 ether
        );
        positions[0] = wethPosition;
        positions[2] = Position({chainId: 1, token: address(wbtc), decimals: 8, units: wbtcUnits});

        // create new slice token with these positions
        address newSlice = core.createSlice("Test", "T", positions);
        sliceToken = SliceToken(newSlice);
        wethUnits = wethUnits + 10 ether;

        // mint slice token
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

        bytes32 expectedMigrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);

        // do migrate into slice token 2
        migrator.migrateStep2(expectedMigrationId, fees);

        uint256 wethBalanceMigratorBefore = weth.balanceOf(address(migrator));
        assertEq(wethBalanceMigratorBefore, wethUnits - 10 ether);

        // withdraw leftover assets
        migrator.withdrawLeftoverAssets(expectedMigrationId);

        vm.expectRevert(
            abi.encodeWithSelector(ISliceTokenMigrator.ActionAlreadyExecuted.selector, "withdrawLeftoverAssets")
        );
        migrator.withdrawLeftoverAssets(expectedMigrationId);
    }

    /* =========================================================== */
    /*   ===============  withrawRedeemedAssets  ===============   */
    /* =========================================================== */
    function test_withrawRedeemedAssets() public {
        vm.startPrank(dev);
        // do migrate step 1
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

        // do migrate step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        // check balance before
        uint256 migratorWbtcBalanceBefore = wbtc.balanceOf(address(migrator));
        uint256 userWbtcBalanceBefore = wbtc.balanceOf(dev);

        assertEq(migratorWbtcBalanceBefore, wbtcUnits);

        // do withdraw redeemed assets
        migrator.withdrawRedeemedAssets(expectedMigrationId);

        // check balance after
        uint256 migratorWbtcBalanceAfter = wbtc.balanceOf(address(migrator));
        uint256 userWbtcBalanceAfter = wbtc.balanceOf(dev);

        assertEq(migratorWbtcBalanceAfter, 0);
        assertEq(userWbtcBalanceAfter, userWbtcBalanceBefore + wbtcUnits);
        vm.stopPrank();
    }

    function test_withrawRedeemedAssets_crossChain() public {
        migrateStep1CrossChain();

        bytes32 expectedMigrationId = 0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d;
        uint128[] memory fees = new uint128[](1);
        fees[0] = 1 ether;

        vm.startPrank(dev);
        deal(address(weth), address(migrator), wethUnits);
        deal(address(link), address(migrator), linkUnits);
        deal(address(uniswap), address(migrator), uniUnits);

        migrator.migrateStep2{value: 1 ether}(expectedMigrationId, fees);

        migrator.withdrawRedeemedAssets(expectedMigrationId);

        MigratorCrossChainSignal[] memory ccsMsgs = new MigratorCrossChainSignal[](1);
        MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
            ccsType: MigratorCrossChainSignalType.WITHDRAW,
            underlying: address(wmaticPolygon),
            user: address(dev),
            amount: wmaticUnits
        });
        ccsMsgs[0] = ccs;
        bytes memory ccsEncoded = abi.encode(ccsMsgs);
        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(migrator)))), nonce: 1});
        makePersistent(address(migrator));

        selectPolygon();

        uint256 mBalanceBefore = wmaticPolygon.balanceOf(address(migrator));
        assertEq(mBalanceBefore, wmaticUnits);

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(address(migrator)).lzReceive{value: 160 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 mBalanceAfter = wmaticPolygon.balanceOf(address(migrator));
        assertEq(mBalanceAfter, 0);
    }

    function test_cannot_withrawRedeemedAssets_Unauthorized() public {
        vm.startPrank(dev);
        // do migrate step 1
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

        // do migrate step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        vm.stopPrank();

        // do withdraw redeemed assets
        vm.expectRevert(ISliceTokenMigrator.Unauthorized.selector);
        migrator.withdrawRedeemedAssets(expectedMigrationId);
    }

    function test_cannot_withrawRedeemedAssets_InvalidTransactionState() public {
        vm.startPrank(dev);
        // do migrate step 1
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

        vm.expectRevert(ISliceTokenMigrator.InvalidTransactionState.selector);
        migrator.withdrawRedeemedAssets(expectedMigrationId);
    }

    function test_cannot_withrawRedeemedAssets_ActionAlreadyExecuted() public {
        vm.startPrank(dev);
        // do migrate step 1
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

        // do migrate step 2
        bytes32 expectedMigrationId = 0x7fce1824a9987df9a13ce937a393bf080f0296c22f44e57f8e5623951a4be9f9;

        deal(address(uniswap), address(dev), uniUnits);
        uniswap.transfer(address(migrator), uniUnits);
        migrator.migrateStep2(expectedMigrationId, fees);

        // do withdraw redeemed assets
        migrator.withdrawRedeemedAssets(expectedMigrationId);

        vm.expectRevert(
            abi.encodeWithSelector(ISliceTokenMigrator.ActionAlreadyExecuted.selector, "withdrawRedeemedAssets")
        );
        migrator.withdrawRedeemedAssets(expectedMigrationId);

        vm.stopPrank();
    }

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

    function migrateStep1CrossChain() internal {
        vm.startPrank(dev);
        deployTestContracts(ChainSelect.POLYGON, "", positions);
        selectMainnet();
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

        makePersistent(address(migrator));
        vm.stopPrank();

        (, bytes32 redeemId,,,,,,) =
            migrator.migrationInfos(0xbbd55424d1496b80b611ab139f3f8f76ac8e05abf8afe83cc99178033a18156d);

        CrossChainSignal[] memory ccsMsgs2 = new CrossChainSignal[](1);
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: redeemId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REDEEM_COMPLETE,
            success: true,
            user: dev,
            underlying: address(wmaticPolygon),
            units: TokenAmountUtils.calculateAmountOutMin(migrateUnits, wmaticUnits, 18),
            value: 0
        });
        ccsMsgs2[0] = _ccsResponse2;
        bytes memory ccsEncoded = abi.encode(ccsMsgs2);

        Origin memory origin2 = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(address(core)).lzReceive(origin2, bytes32(0), ccsEncoded, dev, bytes(""));

        vm.stopPrank();
    }

    function migrateStep2CrossChain() internal {
        vm.startPrank(dev);
        (,,, address polyMigrator) = deployTestContracts(ChainSelect.POLYGON, "", positions);
        selectMainnet();
        deal(dev, 10 ether);
        deal(address(migrator), 10 ether);

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions[0] = Position(1, address(weth), 18, wethUnits);
        ccPositions.push(ccPos);

        address newSliceToken = core.createSlice("new cc token", "ncc", ccPositions);
        ccToken = SliceToken(newSliceToken);
        makePersistent(newSliceToken);

        positions[0] = Position(1, address(weth), 18, wethUnits);
        positions[2] = Position(137, address(wmaticPolygon), 18, wmaticUnits + 100 ether);
        address newLocalSlice = core.createSlice("new local", "nl", positions);
        sliceToken = SliceToken(newLocalSlice);
        makePersistent(newLocalSlice);

        deal(address(weth), address(core), wethUnits);
        deal(address(link), address(core), linkUnits);
        deal(address(wbtc), address(core), wbtcUnits);
        deal(address(uniswap), address(core), uniUnits);

        deal(address(sliceToken), address(dev), migrateUnits);

        sliceToken.approve(address(migrator), migrateUnits);

        uint128[] memory fees = new uint128[](1);
        fees[0] = 1 ether;
        migrator.migrateStep1{value: 1.5 ether}(address(sliceToken), address(ccToken), migrateUnits, fees);
        vm.stopPrank();

        MigratorCrossChainSignal[] memory ccsMsgs = new MigratorCrossChainSignal[](1);
        MigratorCrossChainSignal memory ccs = MigratorCrossChainSignal({
            ccsType: MigratorCrossChainSignalType.APPROVE_TRANSFER,
            underlying: address(wmaticPolygon),
            user: address(core),
            amount: wmaticUnits
        });

        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);
        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(migrator)))), nonce: 1});
        makePersistent(address(migrator));

        selectPolygon();

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polyMigrator).lzReceive{value: 160 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 allowanceMatic = wmaticPolygon.allowance(address(polyMigrator), address(core));
        assertEq(allowanceMatic, wmaticUnits);

        // user has to transfer assets to migrator beforehand
        deal(address(wmaticPolygon), address(migrator), wmaticUnits + 100 ether);

        selectMainnet();

        bytes32 expectedMigrationId = 0xf9b2b245d7a63560f05170c070a2d82e7ad17ee43d83b9921be81ede27716cda;

        (, bytes32 redeemId,,,,,,) = migrator.migrationInfos(expectedMigrationId);

        {
            CrossChainSignal[] memory ccsMsgs3 = new CrossChainSignal[](1);
            CrossChainSignal memory _ccsResponse3 = CrossChainSignal({
                id: redeemId,
                srcChainId: uint32(137),
                ccsType: CrossChainSignalType.REDEEM_COMPLETE,
                success: true,
                user: address(migrator),
                underlying: address(wmaticPolygon),
                units: TokenAmountUtils.calculateAmountOutMin(migrateUnits, wmaticUnits, 18),
                value: 0
            });
            ccsMsgs3[0] = _ccsResponse3;
            ccsEncoded = abi.encode(ccsMsgs3);

            Origin memory origin3 = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

            vm.prank(getAddress("mainnet.layerZeroEndpoint"));
            IOAppReceiver(address(core)).lzReceive(origin3, bytes32(0), ccsEncoded, dev, bytes(""));
        }

        vm.prank(dev);
        migrator.migrateStep2{value: 1.5 ether}(expectedMigrationId, fees);

        selectPolygon();
        vm.prank(address(polyMigrator));
        wmaticPolygon.transfer(address(core), wmaticUnits);

        selectMainnet();

        (,,bytes32 mintId,,,,,) = migrator.migrationInfos(expectedMigrationId);

        CrossChainSignal[] memory ccsMsgs2 = new CrossChainSignal[](1);
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(137),
            ccsType: CrossChainSignalType.MINT_COMPLETE,
            success: true,
            user: address(migrator),
            underlying: address(wmaticPolygon),
            units: TokenAmountUtils.calculateAmountOutMin(migrateUnits, wmaticUnits, 18),
            value: 0
        });
        ccsMsgs2[0] = _ccsResponse2;
        ccsEncoded = abi.encode(ccsMsgs2);

        Origin memory origin2 = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(address(core)).lzReceive(origin2, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 mintedBalance = ccToken.balanceOf(address(migrator));

        assertEq(mintedBalance, 1 ether);
    }
}
