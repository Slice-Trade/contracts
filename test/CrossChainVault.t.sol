// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

import {IWETH} from "../src/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";

import {ICrossChainVault} from "../src/CrossChainVault/ICrossChainVault.sol";
import {CrossChainVault} from "../src/CrossChainVault/CrossChainVault.sol";
import "../src/CrossChainVault/CrossChainVaultStructs.sol";
import {SliceCore} from "../src/SliceCore.sol";
import {SliceToken} from "../src/SliceToken.sol";
import {ChainInfo} from "../src/utils/ChainInfo.sol";
import {SliceTokenDeployer} from "../src/utils/SliceTokenDeployer.sol";
import {Chain as SliceChain, Position} from "../src/Structs.sol";

import {IDeployer} from "../script/IDeployer.sol";
import {CrossChainPositionCreator} from "./helpers/CrossChainPositionCreator.sol";

contract CrossChainVaultTest is Helper {
    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720

    CrossChainVault vault;
    CrossChainVault ccVault;
    SliceCore core;
    SliceToken sliceToken;
    SliceToken ccToken;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public link;
    IERC20 public wbtc;

    IERC20 public wmaticPolygon;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK
    uint256 public wbtcUnits = 100000000;

    uint256 wmaticUnits = 95000000000000000000;

    Position[] public positions;

    Position[] public ccPositions;

    CrossChainPositionCreator public ccPosCreator;

    address polygonLink = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;

    enum ChainSelect {
        MAINNET,
        POLYGON,
        OPTIMISM
    }

    /* =========================================================== */
    /*   ======================    setup   ====================    */
    /* =========================================================== */
    function setUp() public {
        vm.startPrank(dev);
        forkMainnet(MAINNET_BLOCK_NUMBER);
        forkPolygon(POLYGON_BLOCK_NUMBER);
        selectMainnet();

        usdc = IERC20(getAddress("mainnet.usdc"));
        link = IERC20(getAddress("mainnet.link"));
        weth = IWETH(getAddress("mainnet.weth"));
        wbtc = IERC20(getAddress("mainnet.wbtc"));

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        fillPositions();

        (address sCore, address sToken, address sVault) = deployTestContracts(ChainSelect.MAINNET, "");
        core = SliceCore(payable(sCore));
        sliceToken = SliceToken(payable(sToken));

        Position memory ccPos = Position(137, address(wmaticPolygon), 18, wmaticUnits);
        ccPositions.push(ccPos);
        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);
        ccToken = SliceToken(ccTokenAddr);

        vault = CrossChainVault(payable(sVault));

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==============  createCommitmentStrategy  =============   */
    /* =========================================================== */
    function test_createCommitmentStrategy() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.expectEmit(true, false, false, false);
        emit ICrossChainVault.CommitmentStrategyCreated(_stratId);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);

        (
            bytes32 id,
            CommitmentStrategyType stratType,
            CommitmentStrategyState stratState,
            address creator,
            address token,
            uint256 target,
            bool isPrivate
        ) = vault.commitmentStrategies(_stratId);

        assertEq(id, _stratId);
        assertEq(creator, dev);
        assertEq(token, address(sliceToken));
        assertEq(target, 10);

        assertEq(uint8(stratType), 0);
        assertEq(uint8(stratState), 0);

        assertFalse(isPrivate);

        vm.stopPrank();
    }

    function test_cannot_createCommitmentStrategy_vaultIsPaused() public {
        vm.prank(dev);
        vault.pauseVault();
        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        vm.stopPrank();
    }

    function test_cannot_createCommitmentStrategy_notRegisteredSliceToken() public {
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        vault.createCommitmentStrategy(address(0), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
    }

    function test_cannot_createCommitmentStrategy_invalidAmount() public {
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.createCommitmentStrategy(address(sliceToken), 0, CommitmentStrategyType.AMOUNT_TARGET, false);
    }

    function test_cannot_createCommitmentStrategy_invalidTimestamp() public {
        vm.expectRevert(bytes4(keccak256("InvalidTimestamp()")));
        vault.createCommitmentStrategy(address(sliceToken), 0, CommitmentStrategyType.TIMESTAMP_TARGET, false);
    }

    function test_cannot_createCommitmentStrategy_invalidTimeInterval() public {
        vm.expectRevert(bytes4(keccak256("InvalidTimeInterval()")));
        vault.createCommitmentStrategy(address(sliceToken), 0, CommitmentStrategyType.TIME_INTERVAL_TARGET, false);
    }

    /* =========================================================== */
    /*  ===========  modfifyCommitmentStrategyTarget  ===========  */
    /* =========================================================== */
    function test_modifyCommitmentStrategyTarget() public {
        vm.startPrank(dev);
        // TEST AMOUNT TARGET
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratId, 30);
        vault.modifyCommitmentStrategyTarget(_stratId, 30);

        (,,,,, uint256 target,) = vault.commitmentStrategies(_stratId);
        assertEq(target, 30);

        // TEST TIMESTAMP TARGET
        bytes32 _stratIdTstamp = 0x748de79fd9c05cbdcc76d223a55ad13909533d43eceb0f9abf6af133d8d8e68a;
        vault.createCommitmentStrategy(
            address(sliceToken), block.timestamp + 86400, CommitmentStrategyType.TIMESTAMP_TARGET, false
        );

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratIdTstamp, block.timestamp + 43200);
        vault.modifyCommitmentStrategyTarget(_stratIdTstamp, block.timestamp + 43200);

        (,,,,, uint256 target2,) = vault.commitmentStrategies(_stratIdTstamp);
        assertEq(target2, block.timestamp + 43200);

        // TEST TIME INTERVAL TARGET
        bytes32 _stratIdTInterval = 0x671bc5ce24789f79e8138a34a0889b0871fde07844075ddcce104f15845e1353;
        vault.createCommitmentStrategy(address(sliceToken), 3600, CommitmentStrategyType.TIME_INTERVAL_TARGET, false);

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratIdTInterval, 3601);
        vault.modifyCommitmentStrategyTarget(_stratIdTInterval, 3601);

        (,,,,, uint256 target3,) = vault.commitmentStrategies(_stratIdTInterval);
        assertEq(target3, 3601);
    }

    function test_cannot_modifyCommitmentStrategyTarget_VaultIsPaused() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vault.pauseVault();
        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 20);
        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidStrategyId() public {
        vm.expectRevert(bytes4(keccak256("InvalidStrategyId()")));
        vault.modifyCommitmentStrategyTarget(bytes32(0), 10);
    }

    function test_cannot_modifyCommitmentStrategyTarget_NotStrategyCreator() public {
        vm.prank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 30);
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidState() public {
        // TODO
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidAmount() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 0);
        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidTimestamp() public {
        vm.startPrank(dev);
        bytes32 _stratIdTstamp = 0x41fa7ac187f1ee721253fe9753699724c2efb0928b9219c978f2745f015ec290;
        vault.createCommitmentStrategy(
            address(sliceToken), block.timestamp + 86400, CommitmentStrategyType.TIMESTAMP_TARGET, false
        );

        vm.expectRevert(bytes4(keccak256("InvalidTimestamp()")));
        vault.modifyCommitmentStrategyTarget(_stratIdTstamp, block.timestamp - 1);

        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidTimeInterval() public {
        vm.startPrank(dev);
        bytes32 _stratIdTInterval = 0x8b60ffb732aea1f9395fa242dd8f4b329d0087156cbc3562780d934808e319fd;
        vault.createCommitmentStrategy(address(sliceToken), 3600, CommitmentStrategyType.TIME_INTERVAL_TARGET, false);

        vm.expectRevert(bytes4(keccak256("InvalidTimeInterval()")));
        vault.modifyCommitmentStrategyTarget(_stratIdTInterval, 3599);

        vm.stopPrank();
    }

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
    function test_commitToStrategy() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        // mint the tokens to the user
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(vault), wethUnits);
        link.approve(address(vault), linkUnits);
        wbtc.approve(address(vault), wbtcUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](3);
        assets[0] = address(weth);
        assets[1] = address(link);
        assets[2] = address(wbtc);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = wethUnits;
        amounts[1] = linkUnits;
        amounts[2] = wbtcUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = 0xce4f84046022cf17384e9ca29bffc4e1f4f585d620b907bb0ac24f8e50d09bed;
        bytes32 _commitmentId1 = 0x28427307703480c50d36de6e1dfdf3cd867e8f557a55ded07ac78b35f63a97df;
        bytes32 _commitmentId2 = 0xc11b092955f7adee9836b0a5ceb5b474d689a251d764a91e4dc4f6720ce1506d;

        // check that event is emitted
        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommittedToStrategy(_stratId, _commitmentId0);
        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommittedToStrategy(_stratId, _commitmentId1);
        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommittedToStrategy(_stratId, _commitmentId2);

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        assertTransferredAndAllowances();

        bytes32[] memory commitmentIds = new bytes32[](3);
        commitmentIds[0] = _commitmentId0;
        commitmentIds[1] = _commitmentId1;
        commitmentIds[2] = _commitmentId2;

        for (uint256 i = 0; i < commitmentIds.length; i++) {
            assertCommitment(commitmentIds[i], _stratId, assets[i], amounts[i]);
            // check that committed amounts per strategy updated
            uint256 committedPerStrat = vault.committedAmountsPerStrategy(_stratId, assets[i]);
            assertEq(committedPerStrat, amounts[i]);
            // check that commitments for strategy updated
            bytes32 strategyIdAddressHash = keccak256(abi.encode(_stratId, dev));
            bytes32 commId = vault.userCommitmentsForStrategy(strategyIdAddressHash, i);
            assertEq(commitmentIds[i], commId);
        }
        vm.stopPrank();
    }

    function test_commitToStrategy_crossChain() public {
        (bytes32 _stratId, bytes32 expectedCommitId,) = commitCrossChain();
        _verifyCommitment(_stratId, expectedCommitId);
    }

    function test_commitToStrategy_crossChain_Fuzz() public {
        // TODO
    }

    function test_commitToStrategy_TooMuchInCappedAtMax() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        // verify that even if user commits more than the target, only the max target amount will be charged
        deal(address(weth), address(dev), wethUnits * 10);
        weth.approve(address(vault), wethUnits * 10);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits * 10;

        uint128[] memory fees;

        bytes32 _commitmentId = 0xce4f84046022cf17384e9ca29bffc4e1f4f585d620b907bb0ac24f8e50d09bed;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        (,,,,,, uint256 committed,) = vault.commitments(_commitmentId);
        assertEq(committed, wethUnits);

        uint256 committedPerStrat = vault.committedAmountsPerStrategy(_stratId, assets[0]);
        assertEq(committedPerStrat, wethUnits);

        bytes32 strategyIdAddressHash = keccak256(abi.encode(_stratId, dev));
        bytes32 commId = vault.userCommitmentsForStrategy(strategyIdAddressHash, 0);
        assertEq(_commitmentId, commId);
        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_InvalidStrategyId() public {
        bytes32 _stratId = 0xef9820b1b961524a73d3153985dfff86bdaf36b2c25ddc465bf9c7366ba71afa;
        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vm.expectRevert(bytes4(keccak256("InvalidStrategyId()")));
        vault.commitToStrategy(_stratId, assets, amounts, fees);
    }

    function test_cannot_commitToStrategy_InvalidStrategyState() public {
        // TODO
    }

    function test_cannot_commitToStrategy_UnapprovedUser() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, true);

        deal(address(weth), address(dev), wethUnits);
        weth.approve(address(vault), wethUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits * 10;

        uint128[] memory fees;

        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.commitToStrategy(_stratId, assets, amounts, fees);
        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_InvalidAsset() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        address[] memory assets = new address[](1);
        assets[0] = address(makeAddr("random"));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // make sure that no commitment were created
        bytes32 strategyIdAddressHash = keccak256(abi.encode(_stratId, dev));
        vm.expectRevert();
        vault.userCommitmentsForStrategy(strategyIdAddressHash, 0);

        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_InsufficientAmountBalance() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        deal(address(weth), address(dev), wethUnits - 1);
        weth.approve(address(vault), wethUnits - 1);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vm.expectRevert();
        vault.commitToStrategy(_stratId, assets, amounts, fees);
        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_MissingApproval() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        deal(address(weth), address(dev), wethUnits);
        //weth.approve(address(vault), wethUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vm.expectRevert();
        vault.commitToStrategy(_stratId, assets, amounts, fees);
        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_InsufficientFeeForCrossChainCommit() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0xd60d97ebaeb61f838195ec878d904bacc4f94ebb6c79085528b7cc8c9fefa86d;

        selectPolygon();

        (,, address polyVault) = deployTestContracts(ChainSelect.POLYGON, "");
        assertEq(polyVault, address(vault));

        deal(address(wmaticPolygon), address(dev), wmaticUnits);
        wmaticPolygon.approve(address(vault), wmaticUnits);

        selectMainnet();
        deal(dev, 10 ether);

        address[] memory assets = new address[](1);
        assets[0] = address(wmaticPolygon);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wmaticUnits;

        uint128[] memory fees = new uint128[](1);
        fees[0] = 60 ether;

        vault.createCommitmentStrategy(address(ccToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);
        vault.commitToStrategy{value: 1 ether}(_stratId, assets, amounts, fees);

        CrossChainVaultSignal[] memory ccsMsgs = new CrossChainVaultSignal[](1);

        CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
            id: _stratId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.COMMIT,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 1 ether
        });

        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(vault)))), nonce: 1});

        makePersistent(address(vault));

        selectPolygon();
        deal(address(wmaticPolygon), dev, wmaticUnits);
        IERC20(wmaticPolygon).approve(address(vault), wmaticUnits);

        IOAppCore(polyVault).setPeer(30101, bytes32(uint256(uint160(address(vault)))));

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        vm.expectRevert();
        IOAppReceiver(polyVault).lzReceive{value: 1 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));
    }

    /* =========================================================== */
    /*  ============  removeCommitmentFromStrategy  =============  */
    /* =========================================================== */
    function test_removeCommitmentFromStrategy() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);
        deal(address(wbtc), address(dev), wbtcUnits);

        weth.approve(address(vault), wethUnits);
        link.approve(address(vault), linkUnits);
        wbtc.approve(address(vault), wbtcUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](3);
        assets[0] = address(weth);
        assets[1] = address(link);
        assets[2] = address(wbtc);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = wethUnits;
        amounts[1] = linkUnits;
        amounts[2] = wbtcUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = 0xce4f84046022cf17384e9ca29bffc4e1f4f585d620b907bb0ac24f8e50d09bed;
        bytes32 _commitmentId1 = 0x28427307703480c50d36de6e1dfdf3cd867e8f557a55ded07ac78b35f63a97df;
        bytes32 _commitmentId2 = 0xc11b092955f7adee9836b0a5ceb5b474d689a251d764a91e4dc4f6720ce1506d;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        vault.removeCommitmentFromStrategy(_commitmentId0, wethUnits, 0);
        vault.removeCommitmentFromStrategy(_commitmentId1, linkUnits, 0);
        vault.removeCommitmentFromStrategy(_commitmentId2, wbtcUnits, 0);

        bytes32[] memory commitmentIds = new bytes32[](3);
        commitmentIds[0] = _commitmentId0;
        commitmentIds[1] = _commitmentId1;
        commitmentIds[2] = _commitmentId2;

        for (uint256 i = 0; i < commitmentIds.length; i++) {
            amounts[i] = 0;
            assertCommitment(commitmentIds[i], _stratId, assets[i], amounts[i]);
            uint256 committedPerStrat = vault.committedAmountsPerStrategy(_stratId, assets[i]);
            assertEq(committedPerStrat, amounts[i]);
        }
    }

    function test_removeCommitmentFromStrategy_crossChain() public {
        (bytes32 strategyId, bytes32 commitmentId, address polyVault) = commitCrossChain();
        vm.prank(dev);
        vault.removeCommitmentFromStrategy{value: 1 ether}(commitmentId, wmaticUnits, 60 ether);

        CrossChainVaultSignal[] memory ccsMsgs = new CrossChainVaultSignal[](1);

        CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
            id: commitmentId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.REMOVE,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 60 ether
        });

        ccsMsgs[0] = ccs;
        bytes memory ccsEncoded = abi.encode(ccsMsgs);
        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(vault)))), nonce: 1});

        makePersistent(address(vault));

        selectPolygon();
        vm.prank(dev);
        IOAppCore(polyVault).setPeer(30101, bytes32(uint256(uint160(address(vault)))));

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polyVault).lzReceive{value: 60 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 balance = wmaticPolygon.balanceOf(polyVault);
        assertEq(0, balance);
        uint256 balanceUser = wmaticPolygon.balanceOf(dev);
        assertEq(wmaticUnits, balanceUser);

        ccs = CrossChainVaultSignal({
            id: commitmentId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.REMOVE_COMPLETE,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 0
        });

        ccsMsgs[0] = ccs;
        ccsEncoded = abi.encode(ccsMsgs);

        origin = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polyVault)))), nonce: 1});

        selectMainnet();

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.prank(getAddress("mainnet.layerZeroEndpoint"));

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.RemovedCommitmentFromStrategy(commitmentId, wmaticUnits);
        IOAppReceiver(address(vault)).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        assertCommitment(commitmentId, strategyId, address(wmaticPolygon), 0);

        uint256 committedAmountForStrat = vault.committedAmountsPerStrategy(strategyId, address(wmaticPolygon));
        assertEq(committedAmountForStrat, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_InvalidCommitmentId() public {
        vm.expectRevert(bytes4(keccak256("InvalidCommitmentId()")));
        vault.removeCommitmentFromStrategy(bytes32(0), wethUnits, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_NotCommitmentCreator() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        deal(address(weth), address(dev), wethUnits);

        weth.approve(address(vault), wethUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = 0xce4f84046022cf17384e9ca29bffc4e1f4f585d620b907bb0ac24f8e50d09bed;

        vault.commitToStrategy(_stratId, assets, amounts, fees);
        vm.stopPrank();

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.removeCommitmentFromStrategy(_commitmentId0, wethUnits, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_InvalidAmount() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x41be4f1bb4f53f709150c7501c7fcf921dbc240da8ab03ea8ced3905ec299b47;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);

        deal(address(weth), address(dev), wethUnits);

        weth.approve(address(vault), wethUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = 0xce4f84046022cf17384e9ca29bffc4e1f4f585d620b907bb0ac24f8e50d09bed;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.removeCommitmentFromStrategy(_commitmentId0, wethUnits + 1, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_InvalidStrategyState() public {
        // TODO
    }

    function test_cannot_removeCommitmentFromStrategy_InsufficientFeesForCrossChainRemoval() public {
        (, bytes32 commitmentId, address polyVault) = commitCrossChain();
        vm.prank(dev);
        vault.removeCommitmentFromStrategy{value: 1 ether}(commitmentId, wmaticUnits, 60 ether);

        CrossChainVaultSignal[] memory ccsMsgs = new CrossChainVaultSignal[](1);

        CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
            id: commitmentId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.REMOVE,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 1 ether
        });

        ccsMsgs[0] = ccs;
        bytes memory ccsEncoded = abi.encode(ccsMsgs);
        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(vault)))), nonce: 1});

        makePersistent(address(vault));

        selectPolygon();
        vm.prank(dev);
        IOAppCore(polyVault).setPeer(30101, bytes32(uint256(uint160(address(vault)))));

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polyVault).lzReceive{value: 1 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));
    }

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
    function test_changeUserApprovalToCommitmentStrategy() public {
        vm.startPrank(dev);
        // TEST AMOUNT TARGET
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, true);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.expectEmit(true, true, true, false);
        emit ICrossChainVault.ChangedUserApprovalToCommitmentStrategy(_stratId, users[1], true);
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);

        bytes32 strategyIdAddressHash = keccak256(abi.encode(_stratId, users[1]));
        bool isUserApproved = vault.approvedForPrivateStrategy(strategyIdAddressHash);

        assertTrue(isUserApproved);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_VaultIsPaused() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, true);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vault.pauseVault();

        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_InvalidStrategyId() public {
        vm.expectRevert(bytes4(keccak256("InvalidStrategyId()")));
        vault.changeUserApprovalToCommitmentStrategy(bytes32(0), users[1], true);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_NotStrategyCreator() public {
        vm.prank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, true);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_NotPrivateStrategy() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0xebc2ab8e2c3a1930ada96b508920f176160de7fcabb6bfd76c953cb5d48dd002;

        vm.expectRevert(bytes4(keccak256("StrategyNotPrivate()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
        vm.stopPrank();
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_InvalidStrategyState() public {
        // TODO
    }

    /* =========================================================== */
    /*  ======================  pauseVault  =====================  */
    /* =========================================================== */
    function test_pauseVault() public {
        vm.prank(dev);
        vault.pauseVault();
        bool isPaused = vault.isPaused();
        assertTrue(isPaused);
    }

    function test_cannot_pauseVault_NotOwner() public {
        vm.prank(users[1]);
        vm.expectRevert();
        vault.pauseVault();
    }

    function test_cannot_pauseVault_AlreadyPaused() public {
        vm.startPrank(dev);
        vault.pauseVault();

        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.pauseVault();
        vm.stopPrank();
    }

    /* =========================================================== */
    /*  ====================  restartVault  =====================  */
    /* =========================================================== */
    function test_restartVault() public {
        vm.startPrank(dev);
        vault.pauseVault();

        vault.restartVault();
        bool isPaused = vault.isPaused();
        assertFalse(isPaused);
        vm.stopPrank();
    }

    function test_cannot_restartVault_NotOwner() public {
        vm.prank(dev);
        vault.pauseVault();

        vm.prank(users[1]);
        vm.expectRevert();
        vault.restartVault();
    }

    function test_cannot_restartVault_NotPaused() public {
        vm.prank(dev);
        vm.expectRevert(bytes4(keccak256("VaultNotPaused()")));
        vault.restartVault();
    }

    /* =========================================================== */
    /*  ======================  helpers  ========================  */
    /* =========================================================== */
    function deployTestContracts(ChainSelect chainSelect, string memory salt)
        internal
        returns (address sliceCore, address tokenAddr, address sVault)
    {
        if (chainSelect == ChainSelect.MAINNET) {
            selectMainnet();
        } else if (chainSelect == ChainSelect.POLYGON) {
            selectPolygon();
        } else if (chainSelect == ChainSelect.OPTIMISM) {
            selectOptimism();
        }

        ChainInfo chainInfo = new ChainInfo();

        SliceTokenDeployer deployer = new SliceTokenDeployer();

        address endpoint = getAddress(
            chainSelect == ChainSelect.MAINNET
                ? "mainnet.layerZeroEndpoint"
                : (chainSelect == ChainSelect.POLYGON ? "polygon.layerZeroEndpoint" : "optimism.layerZeroEndpoint")
        );

        bytes memory byteCode = abi.encodePacked(
            type(SliceCore).creationCode, abi.encode(endpoint, address(chainInfo), address(deployer), dev)
        );

        IDeployer create3Deployer = IDeployer(
            getAddress(
                chainSelect == ChainSelect.MAINNET
                    ? "mainnet.deployer.create3"
                    : (chainSelect == ChainSelect.POLYGON ? "polygon.deployer.create3" : "optimism.deployer.create3")
            )
        );

        //address _deployedAddr = create3Deployer.deployedAddress(byteCode, dev, stringToBytes32("TEST"));
        if (stringToBytes32(salt) == bytes32(0)) {
            salt = "TEST";
        }
        sliceCore = create3Deployer.deploy(byteCode, stringToBytes32(salt));

        // enable slice token creation
        SliceCore(payable(sliceCore)).changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        SliceCore(payable(sliceCore)).changeApprovedSliceTokenCreator(dev, true);
        // set peer address
        IOAppCore(sliceCore).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : (chainSelect == ChainSelect.POLYGON ? 30101 : 30101)),
            bytes32(uint256(uint160(sliceCore)))
        );

        tokenAddr = SliceCore(payable(sliceCore)).createSlice("Slice Token", "SC", positions);

        bytes memory byteCodeVault = abi.encodePacked(
            type(CrossChainVault).creationCode, abi.encode(sliceCore, address(chainInfo), endpoint, dev)
        );

        sVault = create3Deployer.deploy(byteCodeVault, stringToBytes32("testvault"));

        IOAppCore(sVault).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : (chainSelect == ChainSelect.POLYGON ? 30101 : 30101)),
            bytes32(uint256(uint160(sVault)))
        );
    }

    function stringToBytes32(string memory _string) internal pure returns (bytes32 result) {
        require(bytes(_string).length <= 32, "String too long"); // Ensure string length is not greater than 32 bytes

        assembly {
            result := mload(add(_string, 32))
        }
    }

    function fillPositions() internal {
        // create positions
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            18,
            wethUnits // 0.1 wETH
        );

        Position memory linkPosition = Position(
            1, // mainnet
            address(link), // chainlink
            18,
            linkUnits // 20 LINK
        );

        Position memory wbtcPosition = Position({chainId: 1, token: address(wbtc), decimals: 8, units: wbtcUnits});

        positions.push(wethPosition);
        positions.push(linkPosition);
        positions.push(wbtcPosition);
    }

    function commitCrossChain() private returns (bytes32, bytes32, address) {
        vm.startPrank(dev);
        bytes32 _stratId = 0xd60d97ebaeb61f838195ec878d904bacc4f94ebb6c79085528b7cc8c9fefa86d;

        selectPolygon();

        (address polygonCore,, address polyVault) = deployTestContracts(ChainSelect.POLYGON, "");
        assertEq(polyVault, address(vault));

        deal(address(wmaticPolygon), address(dev), wmaticUnits);
        wmaticPolygon.approve(address(vault), wmaticUnits);

        selectMainnet();
        deal(dev, 10 ether);

        address[] memory assets = new address[](1);
        assets[0] = address(wmaticPolygon);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wmaticUnits;

        uint128[] memory fees = new uint128[](1);
        fees[0] = 60 ether;

        vault.createCommitmentStrategy(address(ccToken), 1 ether, CommitmentStrategyType.AMOUNT_TARGET, false);
        vault.commitToStrategy{value: 1 ether}(_stratId, assets, amounts, fees);

        CrossChainVaultSignal[] memory ccsMsgs = new CrossChainVaultSignal[](1);

        CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
            id: _stratId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.COMMIT,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 60 ether
        });

        ccsMsgs[0] = ccs;

        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(vault)))), nonce: 1});

        makePersistent(address(vault));

        selectPolygon();
        deal(address(wmaticPolygon), dev, wmaticUnits);
        IERC20(wmaticPolygon).approve(address(vault), wmaticUnits);

        IOAppCore(polyVault).setPeer(30101, bytes32(uint256(uint160(address(vault)))));

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.stopPrank();

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polyVault).lzReceive{value: 60 ether}(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 balance = wmaticPolygon.balanceOf(polyVault);
        assertEq(wmaticUnits, balance);
        uint256 coreApproval = wmaticPolygon.allowance(polyVault, polygonCore);
        assertEq(balance, coreApproval);

        ccs = CrossChainVaultSignal({
            id: _stratId,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.COMMIT_COMPLETE,
            user: dev,
            underlying: address(wmaticPolygon),
            decimals: 18,
            amount: wmaticUnits,
            value: 0
        });

        ccsMsgs[0] = ccs;
        ccsEncoded = abi.encode(ccsMsgs);

        origin = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polyVault)))), nonce: 1});

        selectMainnet();

        deal(getAddress("polygon.layerZeroEndpoint"), 200 ether);
        vm.prank(getAddress("mainnet.layerZeroEndpoint"));

        bytes32 expectedCommitId = 0x88616547f7cf6e547e69d8cb247098e71e741f8a16f77192583339d17ffeeaf9;

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommittedToStrategy(_stratId, expectedCommitId);
        IOAppReceiver(address(vault)).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        return (_stratId, expectedCommitId, polyVault);
    }

        function bytes32ToHexString(bytes32 _bytes32) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = hexChars[uint256(uint8(_bytes32[i] >> 4))];
            str[1 + i * 2] = hexChars[uint256(uint8(_bytes32[i] & 0x0f))];
        }
        return string(str);
    }

    function assertTransferredAndAllowances() private view {
        // check that funds arrived to the vault
        uint256 wethBalance = weth.balanceOf(address(vault));
        uint256 linkBalance = link.balanceOf(address(vault));
        uint256 wbtcBalance = wbtc.balanceOf(address(vault));

        assertEq(wethBalance, wethUnits);
        assertEq(linkBalance, linkUnits);
        assertEq(wbtcBalance, wbtcUnits);

        // check that token approved from vault to slice core
        uint256 wethApproved = weth.allowance(address(vault), address(core));
        uint256 linkApproved = link.allowance(address(vault), address(core));
        uint256 wbtcApproved = wbtc.allowance(address(vault), address(core));

        assertEq(wethApproved, wethUnits);
        assertEq(linkApproved, linkUnits);
        assertEq(wbtcApproved, wbtcUnits);
    }

    function assertCommitment(bytes32 _commitmentId, bytes32 _stratId, address _asset, uint256 _amount) private view {
        // check that commitments updated
        (bytes32 commitmentId, bytes32 strategyId, address creator,, address asset,, uint256 committed, uint256 consumed)
        = vault.commitments(_commitmentId);
        assertEq(commitmentId, _commitmentId);
        assertEq(strategyId, _stratId);
        assertEq(creator, dev);
        assertEq(asset, _asset);
        assertEq(committed, _amount);
        assertEq(consumed, 0);
    }

    function _verifyCommitment(bytes32 expectedStratId, bytes32 expectedCommitId) private view {
        (
            bytes32 commId,
            bytes32 strategyId,
            address creator,
            uint256 chainId,
            address asset,
            ,
            uint256 committed,
            uint256 consumed
        ) = vault.commitments(expectedCommitId);
        assertEq(commId, expectedCommitId);
        assertEq(strategyId, expectedStratId);
        assertEq(creator, dev);
        assertEq(chainId, 137);
        assertEq(asset, address(wmaticPolygon));
        assertEq(committed, wmaticUnits);
        assertEq(consumed, 0);

        bytes32 strategyIdAddressHash = keccak256(abi.encode(expectedStratId, creator));
        bytes32 _commId = vault.userCommitmentsForStrategy(strategyIdAddressHash, 0);
        assertEq(expectedCommitId, _commId);

        uint256 committedAmountForStrat = vault.committedAmountsPerStrategy(expectedStratId, asset);
        assertEq(committedAmountForStrat, committed);
    }
}
