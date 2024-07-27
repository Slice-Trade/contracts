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
