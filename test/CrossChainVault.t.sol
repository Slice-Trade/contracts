// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

import {IWETH} from "../src/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILayerZeroEndpointV2, MessagingParams} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";
import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";

import {ICrossChainVault} from "../src/CrossChainVault/ICrossChainVault.sol";
import {CrossChainVault} from "../src/CrossChainVault/CrossChainVault.sol";
import "../src/CrossChainVault/CrossChainVaultStructs.sol";
import {SliceCore} from "../src/SliceCore.sol";
import {SliceToken} from "../src/SliceToken.sol";
import {ChainInfo} from "../src/utils/ChainInfo.sol";
import {SliceTokenDeployer} from "../src/utils/SliceTokenDeployer.sol";
import {Chain as SliceChain, Position, CrossChainSignal, CrossChainSignalType} from "../src/Structs.sol";
import "../src/external/AggregatorV2V3Interface.sol";
import {TokenAmountUtils} from "../src/libs/TokenAmountUtils.sol";

import {IDeployer} from "../script/IDeployer.sol";
import {CrossChainPositionCreator} from "./helpers/CrossChainPositionCreator.sol";

import {LZFeeEstimator} from "./helpers/LZFeeEstimator.sol";

contract CrossChainVaultTest is Helper {
    using TokenAmountUtils for CrossChainVaultTest;

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

    uint256 wmaticUnits = 95000000000000000000; // 95 wmatic

    Position[] public positions;

    Position[] public ccPositions;

    CrossChainPositionCreator public ccPosCreator;

    address public polyCore;

    address polygonLink = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;

    AggregatorV2V3Interface public wethPriceFeed = AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    AggregatorV2V3Interface public linkPriceFeed = AggregatorV2V3Interface(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c);
    AggregatorV2V3Interface public wbtcPriceFeed = AggregatorV2V3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    AggregatorV2V3Interface public wmaticPriceFeed = AggregatorV2V3Interface(0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676);

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
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.expectEmit(true, false, false, false);
        emit ICrossChainVault.CommitmentStrategyCreated(_stratId);
        vault.createCommitmentStrategy(address(sliceToken), 10, false);

        (bytes32 id, address creator, address token, uint256 target, bool isPrivate, uint256 nonce) =
            vault.commitmentStrategies(_stratId);

        assertEq(id, _stratId);
        assertEq(creator, dev);
        assertEq(token, address(sliceToken));
        assertEq(target, 10);

        assertFalse(isPrivate);
        assertEq(nonce, 0);
        vm.stopPrank();
    }

    function test_cannot_createCommitmentStrategy_vaultIsPaused() public {
        vm.prank(dev);
        vault.pauseVault();
        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        vm.stopPrank();
    }

    function test_cannot_createCommitmentStrategy_notRegisteredSliceToken() public {
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        vault.createCommitmentStrategy(address(0), 10, false);
    }

    function test_cannot_createCommitmentStrategy_invalidAmount() public {
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.createCommitmentStrategy(address(sliceToken), 0, false);
    }

    /* =========================================================== */
    /*  ===========  modfifyCommitmentStrategyTarget  ===========  */
    /* =========================================================== */
    function test_modifyCommitmentStrategyTarget() public {
        vm.startPrank(dev);

        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratId, 30);
        vault.modifyCommitmentStrategyTarget(_stratId, 30);

        (,,, uint256 target,,) = vault.commitmentStrategies(_stratId);
        assertEq(target, 30);
    }

    function test_cannot_modifyCommitmentStrategyTarget_VaultIsPaused() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

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
        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 30);
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidAmount() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 0);
        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_NewTargetTooLow() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);
        bytes32 _stratId = 0x236f8502c965dcf95e2572ddf9303f883c8141e5850173b663476c3e67662722;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        deal(address(weth), address(dev), wethUnits);
        weth.approve(address(vault), wethUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        vm.expectRevert(bytes4(keccak256("NewTargetTooLow()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 0.5 ether);
    }

    /* =========================================================== */
    /*  ==============  executeCommitmentStrategy  =============   */
    /* =========================================================== */
    function test_executeCommitmentStrategy() public {
        // create commitment strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        // set the price feeds
        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
        vault.setPriceFeedForAsset(address(link), linkPriceFeed);
        vault.setPriceFeedForAsset(address(wbtc), wbtcPriceFeed);

        vault.setMaxTimestampDiff(3600);

        deal(address(weth), users[1], wethUnits);
        deal(address(link), users[2], linkUnits);
        deal(address(wbtc), users[3], wbtcUnits);

        vm.stopPrank();

        vm.prank(users[1]);
        weth.approve(address(vault), wethUnits);
        vm.prank(users[2]);
        link.approve(address(vault), linkUnits);
        vm.prank(users[3]);
        wbtc.approve(address(vault), wbtcUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        // commit weth to commitment strategy from account 1
        vm.prank(users[1]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit link to commitment strategy from account 2
        assets[0] = address(link);
        amounts[0] = linkUnits;
        vm.prank(users[2]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit wbtc to commitment strategy from account 3
        vm.prank(users[3]);
        assets[0] = address(wbtc);
        amounts[0] = wbtcUnits;
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        uint256 sliceTokenBalanceBefore = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceBefore, 0);
        // execute the commitment strategy
        vm.prank(dev);
        vault.executeCommitmentStrategy(_stratId, fees);

        // check that balance of vault has been increased to target
        uint256 sliceTokenBalanceAfter = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceAfter, 1 ether);

        // check that strategy nonce has been increased
        (,,,,, uint256 nonce) = vault.commitmentStrategies(_stratId);
        assertEq(nonce, 1);

        Position[] memory _positions = sliceToken.getPositions();

        // check that committed amounts per strategy has been reset to 0
        for (uint256 i = 0; i < _positions.length; i++) {
            uint256 comm = vault.committedAmountsPerStrategy(_stratId, _positions[i].token);
            assertEq(comm, 0);

            // check that oracle prices have been updated
            _verifyOraclePriceUpdate(_stratId, _positions[i].token);
        }
    }

    function test_executeCommitmentStrategy_CrossChain() public {
        (bytes32 strategyId, bytes32 commitmentId, address polyVault) = commitCrossChain();
        executeCrossChain(strategyId);

        // check that execute was successful, vault balance increased
        uint256 ccVaultBalance = ccToken.balanceOf(address(vault));
        assertEq(ccVaultBalance, 1 ether);

        (,,,,, uint256 nonce) = vault.commitmentStrategies(strategyId);
        assertEq(nonce, 1);

        uint256 comms = vault.committedAmountsPerStrategy(strategyId, address(wmaticPolygon));
        assertEq(comms, 0);
    }

    function test_executeCommitmentStrategy_CrossChain_Fuzz() public {
        // TODO
    }

    function test_executeCommitmentStrategy_VaultIsPaused() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        vault.pauseVault();

        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.executeCommitmentStrategy(_stratId, fees);
        vm.stopPrank();
    }

    function test_cannot_executeCommitmentStrategy_TargetNotReached() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        uint128[] memory fees;
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.executeCommitmentStrategy(_stratId, fees);
        vm.stopPrank();
    }

    function test_cannot_executeCommitmentStrategy_OraclePriceStale() public {
        // create commitment strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        // set the price feeds
        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
        vault.setPriceFeedForAsset(address(link), linkPriceFeed);
        vault.setPriceFeedForAsset(address(wbtc), wbtcPriceFeed);

        // vault.setMaxTimestampDiff(3600);

        deal(address(weth), users[1], wethUnits);
        deal(address(link), users[2], linkUnits);
        deal(address(wbtc), users[3], wbtcUnits);

        vm.stopPrank();

        vm.prank(users[1]);
        weth.approve(address(vault), wethUnits);
        vm.prank(users[2]);
        link.approve(address(vault), linkUnits);
        vm.prank(users[3]);
        wbtc.approve(address(vault), wbtcUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        // commit weth to commitment strategy from account 1
        vm.prank(users[1]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit link to commitment strategy from account 2
        assets[0] = address(link);
        amounts[0] = linkUnits;
        vm.prank(users[2]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit wbtc to commitment strategy from account 3
        vm.prank(users[3]);
        assets[0] = address(wbtc);
        amounts[0] = wbtcUnits;
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        uint256 sliceTokenBalanceBefore = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceBefore, 0);
        // execute the commitment strategy
        vm.prank(dev);
        vm.expectRevert(bytes4(keccak256("StalePrice()")));
        vault.executeCommitmentStrategy(_stratId, fees);
    }

    function test_cannot_executeCommitmentStrategy_InsufficientLzFee() public {
        // TODO
    }

    /* =========================================================== */
    /*  ===================  commitToStrategy  =================   */
    /* =========================================================== */
    function test_commitToStrategy() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

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

        bytes32 _commitmentId0 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(weth), uint256(0))
        );
        bytes32 _commitmentId1 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(link), uint256(0))
        );
        bytes32 _commitmentId2 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(wbtc), uint256(0))
        );

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
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        // verify that even if user commits more than the target, only the max target amount will be charged
        deal(address(weth), address(dev), wethUnits * 10);
        weth.approve(address(vault), wethUnits * 10);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits * 10;

        uint128[] memory fees;

        bytes32 _commitmentId = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(weth), uint256(0))
        );

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        (,,,,,,, uint256 committed,) = vault.commitments(_commitmentId);

        assertEq(committed, wethUnits);

        uint256 committedPerStrat = vault.committedAmountsPerStrategy(_stratId, assets[0]);
        assertEq(committedPerStrat, wethUnits);

        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_VaultIsPaused() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        vault.pauseVault();

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vm.expectRevert(bytes4(keccak256("VaultIsPaused()")));
        vault.commitToStrategy(_stratId, assets, amounts, fees);
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

    function test_cannot_commitToStrategy_UnapprovedUser() public {
        // create a strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, true);

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
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        address[] memory assets = new address[](1);
        assets[0] = address(makeAddr("random"));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        Position[] memory _positions = sliceToken.getPositions();
        for (uint256 i = 0; i < _positions.length; i++) {
            bytes32 commitmentId = keccak256(
                abi.encodePacked(
                    CrossChainVault.commitToStrategy.selector, _stratId, dev, _positions[i].token, uint256(0)
                )
            );
            (bytes32 id, bytes32 strategyId,,,,,, uint256 committed,) = vault.commitments(commitmentId);
            assertEq(id, bytes32(0));
            assertEq(strategyId, bytes32(0));
            assertEq(committed, 0);
        }

        vm.stopPrank();
    }

    function test_cannot_commitToStrategy_InsufficientAmountBalance() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

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
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

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
        bytes32 _stratId = 0x860200ef8180fd0973a6a252b60ca04bd649076e56246c907bdf52817689399d;

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

        vault.createCommitmentStrategy(address(ccToken), 1 ether, false);
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
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

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

        bytes32 _commitmentId0 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(weth), uint256(0))
        );
        bytes32 _commitmentId1 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(link), uint256(0))
        );
        bytes32 _commitmentId2 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(wbtc), uint256(0))
        );

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
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        deal(address(weth), address(dev), wethUnits);

        weth.approve(address(vault), wethUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(weth), uint256(0))
        );

        vault.commitToStrategy(_stratId, assets, amounts, fees);
        vm.stopPrank();

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.removeCommitmentFromStrategy(_commitmentId0, wethUnits, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_StrategyAlreadyExecuted() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);
        // set the price feeds
        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
        vault.setPriceFeedForAsset(address(link), linkPriceFeed);
        vault.setPriceFeedForAsset(address(wbtc), wbtcPriceFeed);

        vault.setMaxTimestampDiff(3600);

        deal(address(weth), users[1], wethUnits);
        deal(address(link), users[2], linkUnits);
        deal(address(wbtc), users[3], wbtcUnits);

        vm.stopPrank();

        vm.prank(users[1]);
        weth.approve(address(vault), wethUnits);
        vm.prank(users[2]);
        link.approve(address(vault), linkUnits);
        vm.prank(users[3]);
        wbtc.approve(address(vault), wbtcUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        // commit weth to commitment strategy from account 1
        vm.prank(users[1]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit link to commitment strategy from account 2
        assets[0] = address(link);
        amounts[0] = linkUnits;
        vm.prank(users[2]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit wbtc to commitment strategy from account 3
        vm.prank(users[3]);
        assets[0] = address(wbtc);
        amounts[0] = wbtcUnits;
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        uint256 sliceTokenBalanceBefore = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceBefore, 0);
        // execute the commitment strategy
        vm.prank(dev);
        vault.executeCommitmentStrategy(_stratId, fees);

        bytes32 _commId1 = 0x9137ab68fa7d6e7043e44db6952928c58c6eab6ee9021fc13c08b454ee41e585;
        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("StrategyAlreadyExecuted()")));
        vault.removeCommitmentFromStrategy(_commId1, wethUnits, 0);
    }

    function test_cannot_removeCommitmentFromStrategy_InvalidAmount() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;

        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        deal(address(weth), address(dev), wethUnits);

        weth.approve(address(vault), wethUnits);

        // call commit to strategy with muliple tokens
        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        bytes32 _commitmentId0 = keccak256(
            abi.encodePacked(CrossChainVault.commitToStrategy.selector, _stratId, dev, address(weth), uint256(0))
        );

        vault.commitToStrategy(_stratId, assets, amounts, fees);

        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.removeCommitmentFromStrategy(_commitmentId0, wethUnits + 1, 0);
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
    function test_pullMintedTokenShares() public {
        /* 
            WETH Price:  3634.40000000
            LINK Price:  20.46450600
            WBTC Price:  70877.62121670

            TSVUsd = 1 * TS_usd = (10 * 3634) + (2000 * 20.46450600) + 70877.62121670 = 
            36344 + 40929,012 + 70877.62121670 =
            148150,6332167

            Refer to: src/CrossChainVault/math.md to understand the calculations
         */

        // create, commit to, and execute commitment strategy
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
        vault.setPriceFeedForAsset(address(link), linkPriceFeed);
        vault.setPriceFeedForAsset(address(wbtc), wbtcPriceFeed);

        vault.setMaxTimestampDiff(3600);

        deal(address(weth), users[1], wethUnits);
        deal(address(link), users[2], linkUnits);
        deal(address(wbtc), users[3], wbtcUnits);

        vm.stopPrank();

        vm.prank(users[1]);
        weth.approve(address(vault), wethUnits);
        vm.prank(users[2]);
        link.approve(address(vault), linkUnits);
        vm.prank(users[3]);
        wbtc.approve(address(vault), wbtcUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        // commit weth to commitment strategy from account 1
        vm.prank(users[1]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit link to commitment strategy from account 2
        assets[0] = address(link);
        amounts[0] = linkUnits;
        vm.prank(users[2]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit wbtc to commitment strategy from account 3
        vm.prank(users[3]);
        assets[0] = address(wbtc);
        amounts[0] = wbtcUnits;
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        uint256 sliceTokenBalanceBefore = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceBefore, 0);
        // execute the commitment strategy
        vm.prank(dev);
        vault.executeCommitmentStrategy(_stratId, fees);

        uint256 sliceTokenBalanceAfter = sliceToken.balanceOf(address(vault));
        assertEq(sliceTokenBalanceAfter, 1 ether);

        sliceTokenBalanceBefore = sliceTokenBalanceAfter;

        // pull minted token shares & check correct values received
        vm.prank(users[1]);
        vault.pullMintedTokenShares(_stratId, 0);
        sliceTokenBalanceAfter = sliceToken.balanceOf(address(vault));

        /* 
            User 1:
            Usa = 1 * Uss = 36344 / 148150,6332167 = 0,245317884985612
         */
        uint256 user1Balance = sliceToken.balanceOf(users[1]);
        assertApproxEqAbs(user1Balance, 245317884985612000, 100);

        assertApproxEqAbs(sliceTokenBalanceAfter, 1 ether - user1Balance, 100);

        sliceTokenBalanceBefore = sliceTokenBalanceAfter;

        /* 
            User 2: 
            Usa = 1 * Uss = 40929,012 / 148150,6332167 = 0,276266196852045
         */
        vm.prank(users[2]);
        vault.pullMintedTokenShares(_stratId, 0);
        sliceTokenBalanceAfter = sliceToken.balanceOf(address(vault));

        uint256 user2Balance = sliceToken.balanceOf(users[2]);
        assertApproxEqAbs(user2Balance, 276266196852045000, 300);
        assertApproxEqAbs(sliceTokenBalanceAfter, sliceTokenBalanceBefore - user2Balance, 100);

        sliceTokenBalanceBefore = sliceTokenBalanceAfter;

        /* 
            User 3:
            usa = 1 * Uss = 70877.62121670 / 148150,6332167 = 0,478415918162343
         */
        vm.prank(users[3]);
        vault.pullMintedTokenShares(_stratId, 0);
        sliceTokenBalanceAfter = sliceToken.balanceOf(address(vault));

        uint256 user3Balance = sliceToken.balanceOf(users[3]);
        assertApproxEqAbs(user3Balance, 47841591, 100);
        assertApproxEqAbs(sliceTokenBalanceAfter, sliceTokenBalanceBefore - user3Balance, 100);
    }

    function test_pullMintedTokenShares_CrossChain() public {
        // TODO
    }

    function test_pullMintedTokenShares_CrossChain_Fuzz() public {
        // TODO
    }

    function test_cannot_pullMintedTokenShares_InvalidStrategyId() public {
        vm.expectRevert(bytes4(keccak256("InvalidStrategyId()")));
        vault.pullMintedTokenShares(bytes32(0), 0);
    }

    function test_cannot_pullMintedTokenShares_StrategyNotExecuted() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        vm.expectRevert(bytes4(keccak256("StrategyNotExecuted()")));
        vault.pullMintedTokenShares(_stratId, 1);
        vm.stopPrank();
    }

    function test_cannot_pullMintedTokenShares_AlreadyPulled() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x28cbbe1250d99285a4c007bac00ddf0fb20ea5646ebdfbcf775cb0f7133c02f1;
        vault.createCommitmentStrategy(address(sliceToken), 1 ether, false);

        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
        vault.setPriceFeedForAsset(address(link), linkPriceFeed);
        vault.setPriceFeedForAsset(address(wbtc), wbtcPriceFeed);

        vault.setMaxTimestampDiff(3600);

        deal(address(weth), users[1], wethUnits);
        deal(address(link), users[2], linkUnits);
        deal(address(wbtc), users[3], wbtcUnits);

        vm.stopPrank();

        vm.prank(users[1]);
        weth.approve(address(vault), wethUnits);
        vm.prank(users[2]);
        link.approve(address(vault), linkUnits);
        vm.prank(users[3]);
        wbtc.approve(address(vault), wbtcUnits);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethUnits;

        uint128[] memory fees;

        // commit weth to commitment strategy from account 1
        vm.prank(users[1]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit link to commitment strategy from account 2
        assets[0] = address(link);
        amounts[0] = linkUnits;
        vm.prank(users[2]);
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        // commit wbtc to commitment strategy from account 3
        vm.prank(users[3]);
        assets[0] = address(wbtc);
        amounts[0] = wbtcUnits;
        vault.commitToStrategy(_stratId, assets, amounts, fees);

        vm.prank(dev);
        vault.executeCommitmentStrategy(_stratId, fees);

        vm.startPrank(users[1]);
        vault.pullMintedTokenShares(_stratId, 0);
        vm.expectRevert(bytes4(keccak256("MintedTokenShareAlreadyPulled()")));
        vault.pullMintedTokenShares(_stratId, 0);
        vm.stopPrank();

        vm.startPrank(users[2]);
        vault.pullMintedTokenShares(_stratId, 0);
        vm.expectRevert(bytes4(keccak256("MintedTokenShareAlreadyPulled()")));
        vault.pullMintedTokenShares(_stratId, 0);
        vm.stopPrank();

        vm.startPrank(users[3]);
        vault.pullMintedTokenShares(_stratId, 0);
        vm.expectRevert(bytes4(keccak256("MintedTokenShareAlreadyPulled()")));
        vault.pullMintedTokenShares(_stratId, 0);
        vm.stopPrank();
    }

    /* =========================================================== */
    /* ========== changeUserApprovalToCommitmentStrategy ========= */
    /* =========================================================== */
    function test_changeUserApprovalToCommitmentStrategy() public {
        vm.startPrank(dev);

        vault.createCommitmentStrategy(address(sliceToken), 10, true);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.expectEmit(true, true, true, false);
        emit ICrossChainVault.ChangedUserApprovalToCommitmentStrategy(_stratId, users[1], true);
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);

        bytes32 strategyIdAddressHash = keccak256(abi.encode(_stratId, users[1]));
        bool isUserApproved = vault.approvedForPrivateStrategy(strategyIdAddressHash);

        assertTrue(isUserApproved);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_VaultIsPaused() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, true);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

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
        vault.createCommitmentStrategy(address(sliceToken), 10, true);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
    }

    function test_cannot_changeUserApprovalToCommitmentStrategy_NotPrivateStrategy() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, false);
        bytes32 _stratId = 0xcbb45c72a86d01c3c8003d9bab43a5042576ad23e8eb4b93a093c0f1b3f4f969;

        vm.expectRevert(bytes4(keccak256("StrategyNotPrivate()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
        vm.stopPrank();
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
    /*  ================  setPriceFeedForAsset  =================  */
    /* =========================================================== */
    function test_setPriceFeedForAsset() public {
        vm.prank(dev);
        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);

        AggregatorInterface _priceFeedAddress = vault.priceFeedsForAssets(address(weth));

        assertEq(address(_priceFeedAddress), address(wethPriceFeed));
    }

    function test_cannot_setPriceFeedForAsset_NotOwner() public {
        vm.expectRevert();
        vault.setPriceFeedForAsset(address(weth), wethPriceFeed);
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
            wethUnits
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
        bytes32 _stratId = 0x860200ef8180fd0973a6a252b60ca04bd649076e56246c907bdf52817689399d;

        selectPolygon();

        (address polygonCore,, address polyVault) = deployTestContracts(ChainSelect.POLYGON, "");
        assertEq(polyVault, address(vault));

        polyCore = polygonCore;

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

        vault.createCommitmentStrategy(address(ccToken), 1 ether, false);
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

        bytes32 expectedCommitId = keccak256(
            abi.encodePacked(
                CrossChainVault.commitToStrategy.selector, _stratId, dev, address(wmaticPolygon), uint256(0)
            )
        );

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommittedToStrategy(_stratId, expectedCommitId);
        IOAppReceiver(address(vault)).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        return (_stratId, expectedCommitId, polyVault);
    }

    function executeCrossChain(bytes32 strategyId) private {
        // take polyCore and polyVault
        deal(dev, 100 ether);
        vm.startPrank(dev);
        vault.setMaxTimestampDiff(3000);
        vault.setPriceFeedForAsset(address(wmaticPolygon), wmaticPriceFeed);

        // estimate fee for mint
        (, uint256 feeTotal, uint128[] memory fees, uint256[] memory feesForMsgs) =
            _estimateFee(polyCore, CrossChainSignalType.MINT, CrossChainSignalType.MINT_COMPLETE);

        // call execute commitment strategy
        vault.executeCommitmentStrategy{value: feeTotal}(strategyId, toUint128Array(feesForMsgs));

        // crate cross chain signal for SliceCore
        CrossChainSignal[] memory ccsMsgs = new CrossChainSignal[](ccPositions.length);

        // send cross chain signal for SliceCore
        bytes32 _expMintId = 0x4320aed1d5ca011d776b4ef7e7ae814cb721fb4785e9679770f236b1c76f5518;

        for (uint256 i = 0; i < ccPositions.length; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: _expMintId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.MINT,
                success: false,
                user: address(vault),
                underlying: ccPositions[i].token,
                units: wmaticUnits,
                value: i == 0 ? feesForMsgs[0] : 0
            });

            ccsMsgs[i] = ccs;
        }

        // make SliceCore persistent
        bytes memory ccsEncoded = abi.encode(ccsMsgs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});
        makePersistent(address(ccToken));
        // switch to polygon
        selectPolygon();

        // deal money for gas & msg value to lzendpoint
        uint256 amountOut = TokenAmountUtils.calculateAmountOutMin(1 ether, wmaticUnits, 18);
        for (uint256 i = 0; i < ccPositions.length; i++) {
            deal(ccPositions[i].token, address(vault), amountOut);
            IERC20(ccPositions[i].token).approve(polyCore, amountOut);
        }
        IOAppCore(polyCore).setPeer(30101, bytes32(uint256(uint160(address(core)))));
        deal(polyCore, 0);

        deal(getAddress("polygon.layerZeroEndpoint"), fees[0]);
        vm.stopPrank();

        // call lz receive on SliceCore
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polyCore).lzReceive{value: fees[0]}(origin, bytes32(0), ccsEncoded, address(vault), bytes(""));

        // create response
        for (uint256 i = 0; i < ccPositions.length; i++) {
            CrossChainSignal memory ccs = CrossChainSignal({
                id: _expMintId,
                srcChainId: uint32(block.chainid),
                ccsType: CrossChainSignalType.MINT_COMPLETE,
                success: true,
                user: address(vault),
                underlying: ccPositions[i].token,
                units: wmaticUnits,
                value: 0
            });

            ccsMsgs[i] = ccs;
        }
        bytes memory ccsEncoded2 = abi.encode(ccsMsgs);

        // call response on mainnet on SliceCore
        selectMainnet();
        origin = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polyCore)))), nonce: 1});
        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(origin, bytes32(0), ccsEncoded2, address(vault), bytes(""));
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
        (
            bytes32 commitmentId,
            bytes32 strategyId,
            CommitmentState commitmentState,
            address creator,
            ,
            address asset,
            ,
            uint256 committed,
            uint256 strategyNonce
        ) = vault.commitments(_commitmentId);
        assertEq(commitmentId, _commitmentId);
        assertEq(strategyId, _stratId);
        assertEq(uint256(commitmentState), 0);
        assertEq(creator, dev);
        assertEq(asset, _asset);
        assertEq(committed, _amount);
        assertEq(strategyNonce, 0);
    }

    function _verifyCommitment(bytes32 expectedStratId, bytes32 expectedCommitId) private view {
        (
            bytes32 commId,
            bytes32 strategyId,
            CommitmentState commitmentState,
            address creator,
            uint256 chainId,
            address asset,
            ,
            uint256 committed,
            uint256 strategyNonce
        ) = vault.commitments(expectedCommitId);
        assertEq(commId, expectedCommitId);
        assertEq(strategyId, expectedStratId);
        assertEq(uint256(commitmentState), 0);
        assertEq(creator, dev);
        assertEq(chainId, 137);
        assertEq(asset, address(wmaticPolygon));
        assertEq(committed, wmaticUnits);
        assertEq(strategyNonce, 0);

        uint256 committedAmountForStrat = vault.committedAmountsPerStrategy(expectedStratId, asset);
        assertEq(committedAmountForStrat, committed);
    }

    function _verifyOraclePriceUpdate(bytes32 _stratId, address _token) private view {
        bytes32 strategyIdTokenHash = keccak256(abi.encode(_stratId, _token));
        (bytes32 id, address token, uint8 decimals, uint256 price, uint256 updateTimestamp) =
            vault.oraclePriceUpdates(strategyIdTokenHash);
        assertEq(id, _stratId);
        assertEq(token, _token);
        assertEq(decimals, 8);
        assertGt(price, 0);
        assertGt(updateTimestamp, 1711459720);
    }

    function _estimateFee(address polygonCore, CrossChainSignalType type1, CrossChainSignalType typeRes)
        private
        returns (address, uint256, uint128[] memory, uint256[] memory)
    {
        uint128[] memory fees = new uint128[](1);

        selectPolygon();
        if (polygonCore == address(0)) {
            revert("Polygon core is zero address");
        }

        LZFeeEstimator feeEstimatorPolygon = new LZFeeEstimator(
            SliceCore(payable(polygonCore)),
            SliceCore(payable(polygonCore)).chainInfo(),
            ILayerZeroEndpointV2(getAddress("polygon.layerZeroEndpoint"))
        );
        uint256 polygonFee = feeEstimatorPolygon.estimateLzFeeCompleted(ccPositions, typeRes, 1);
        fees[0] = uint128(polygonFee);

        selectMainnet();

        vm.deal(dev, 100 ether);

        LZFeeEstimator feeEstimator =
            new LZFeeEstimator(core, core.chainInfo(), ILayerZeroEndpointV2(getAddress("polygon.layerZeroEndpoint")));

        uint256[] memory feesForMsgs = feeEstimator.estimateLzFee(address(ccToken), type1, fees);

        uint256 feeTotal;
        for (uint256 i = 0; i < feesForMsgs.length; i++) {
            feeTotal += feesForMsgs[i];
        }

        return (polygonCore, feeTotal, fees, feesForMsgs);
    }

    function toUint128Array(uint256[] memory arr) internal pure returns (uint128[] memory) {
        uint128[] memory _arr = new uint128[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            _arr[i] = uint128(arr[i]);
        }
        return _arr;
    }
}
