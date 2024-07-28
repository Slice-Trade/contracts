// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";

import {IWETH} from "../src/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

contract CrossChainVaultTest is Helper {
    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720

    CrossChainVault vault;
    SliceCore core;
    SliceToken sliceToken;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public link;
    IERC20 public wbtc;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK
    uint256 public wbtcUnits = 100000000;

    Position[] public positions;

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

        fillPositions();

        (address sCore, address sToken) = deployTestContracts(ChainSelect.MAINNET, "");
        core = SliceCore(payable(sCore));
        sliceToken = SliceToken(payable(sToken));

        vault = new CrossChainVault(core, core.chainInfo());
        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==============  createCommitmentStrategy  =============   */
    /* =========================================================== */
    function test_createCommitmentStrategy() public {
        vm.startPrank(dev);
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratId, 30);
        vault.modifyCommitmentStrategyTarget(_stratId, 30);

        (,,,,, uint256 target,) = vault.commitmentStrategies(_stratId);
        assertEq(target, 30);

        // TEST TIMESTAMP TARGET
        bytes32 _stratIdTstamp = 0x24b95feeaea55019b9be6536afa3264a1da0c96c7e28f108923da5a4c711c487;
        vault.createCommitmentStrategy(
            address(sliceToken), block.timestamp + 86400, CommitmentStrategyType.TIMESTAMP_TARGET, false
        );

        vm.expectEmit(true, true, false, false);
        emit ICrossChainVault.CommitmentStrategyTargetModified(_stratIdTstamp, block.timestamp + 43200);
        vault.modifyCommitmentStrategyTarget(_stratIdTstamp, block.timestamp + 43200);

        (,,,,, uint256 target2,) = vault.commitmentStrategies(_stratIdTstamp);
        assertEq(target2, block.timestamp + 43200);

        // TEST TIME INTERVAL TARGET
        bytes32 _stratIdTInterval = 0xda1405ce44946e57f1c1a6e086bfbc349fbce82985b79ba675a1cbd82754b76f;
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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vault.modifyCommitmentStrategyTarget(_stratId, 0);
        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidTimestamp() public {
        vm.startPrank(dev);
        bytes32 _stratIdTstamp = 0x992238cb94270b44f2d5a83ddfdc62f202191ab4088e2b6001188eab0facbb0a;
        vault.createCommitmentStrategy(
            address(sliceToken), block.timestamp + 86400, CommitmentStrategyType.TIMESTAMP_TARGET, false
        );

        vm.expectRevert(bytes4(keccak256("InvalidTimestamp()")));
        vault.modifyCommitmentStrategyTarget(_stratIdTstamp, block.timestamp - 1);
        
        vm.stopPrank();
    }

    function test_cannot_modifyCommitmentStrategyTarget_InvalidTimeInterval() public {
        vm.startPrank(dev);
        bytes32 _stratIdTInterval = 0x60ecb655391dc6f76b72bf58e82aa84db06164ff4308e42b56c7fdf3a13ba0fb;
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
    function test_changeUserApprovalToCommitmentStrategy() public {
        vm.startPrank(dev);
        // TEST AMOUNT TARGET
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, true);
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;
        
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
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

        vm.prank(users[1]);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vault.changeUserApprovalToCommitmentStrategy(_stratId, users[1], true);
    }


    function test_cannot_changeUserApprovalToCommitmentStrategy_NotPrivateStrategy() public {
        vm.startPrank(dev);
        vault.createCommitmentStrategy(address(sliceToken), 10, CommitmentStrategyType.AMOUNT_TARGET, false);
        bytes32 _stratId = 0x6872a8edab10171a6bd411d9d71d1cd97986f9ba7f0f1e97e73ba2d9be9462fe;

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
        returns (address sliceCore, address tokenAddr)
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
}
