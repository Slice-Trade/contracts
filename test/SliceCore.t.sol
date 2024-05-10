// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOAppReceiver, Origin} from "@lz-oapp-v2/interfaces/IOAppReceiver.sol";
import {IOAppCore} from "@lz-oapp-v2/interfaces/IOAppCore.sol";

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "./helpers/Helper.sol";
import "../src/external/IWETH.sol";

import "../src/utils/ChainInfo.sol";

import "../src/interfaces/ISliceCoreErrors.sol";
import "../src/SliceCore.sol";
import "../src/SliceToken.sol";
import "../src/libs/SliceTokenDeployer.sol";

import {IDeployer} from "../script/IDeployer.sol";

// TODO: Wbtc decimals
contract SliceCoreTest is Helper {
    uint256 immutable MAINNET_BLOCK_NUMBER = 19518913; //TSTAMP: 1711459720
    uint256 immutable POLYGON_BLOCK_NUMBER = 55101688; //TSTAMP: 1711459720
    SliceCore core;
    SliceToken token;

    SliceToken ccToken;

    IWETH public weth;
    IERC20 public usdc;
    IERC20 public link;

    IERC20 public wmaticPolygon;

    Position[] public positions;

    uint256 maxEstWethPrice = 40000000000; // 40000 usdc
    uint256 maxEstLinkPrice = 45000000000; // 45000 usdc

    uint256 constant MAX_ESTIMATED_PRICE = 160000000000; // 160000 USDC

    uint256[] public maxEstimatedPrices;

    uint256 public wethUnits = 10000000000000000000; // 10 wETH
    uint256 public linkUnits = 2000000000000000000000; // 2000 LINK

    uint256[] public wrongPrices;

    bytes[] public routes;

    bytes public usdcWethRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001";
    bytes public usdcLinkRoute =
        hex"01A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB4801ffff00397FF1542f962076d0BFE58eA045FfA2d347ACa001C40D16476380e4037e6b1A2594cAF6a6cc8Da96704C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc200C40D16476380e4037e6b1A2594cAF6a6cc8Da96700";

    /* CROSS_CHAIN */
    uint256 maxWMaticPrice = 100000000; //100usdc
    uint256 wmaticUnits = 95000000000000000000; // 95matic

    uint256[] public maxEstCCPrices;
    Position[] public ccPositions;
    bytes[] public ccRoutes;
    bytes public usdcWmaticRoute =
        hex"012791Bca1f2de4661ED88A30C99A7a9449Aa8417402555500cd353F79d9FADe311fC3119B841e1f456b54e85800eeb3e0999D01f0d1Ed465513E414725a357F6ae4ffff0121988C9CFD08db3b5793c2C6782271dC9474925100";

    enum ChainSelect {
        MAINNET,
        POLYGON
    }

    address polygonLink = 0xb0897686c545045aFc77CF20eC7A532E3120E0F1;

    function deployTestContracts(ChainSelect chainSelect) internal returns (address sliceCore, address tokenAddr) {
        if (chainSelect == ChainSelect.MAINNET) {
            selectMainnet();
        } else if (chainSelect == ChainSelect.POLYGON) {
            selectPolygon();
        }

        ChainInfo chainInfo = new ChainInfo();

        SliceTokenDeployer deployer = new SliceTokenDeployer();

        bytes memory byteCode = abi.encodePacked(
            type(SliceCore).creationCode,
            abi.encode(
                getAddress(chainSelect == ChainSelect.MAINNET ? "mainnet.usdc" : "polygon.usdc"),
                getAddress(chainSelect == ChainSelect.MAINNET ? "mainnet.sushiXSwap" : "polygon.sushiXSwap"),
                getAddress(chainSelect == ChainSelect.MAINNET ? "mainnet.stargateAdapter" : "polygon.stargateAdapter"),
                getAddress(chainSelect == ChainSelect.MAINNET ? "mainnet.axelarAdapter" : "polygon.axelarAdapter"),
                getAddress(
                    chainSelect == ChainSelect.MAINNET ? "mainnet.layerZeroEndpoint" : "polygon.layerZeroEndpoint"
                ),
                address(chainInfo),
                address(deployer),
                dev
            )
        );

        IDeployer create3Deployer = IDeployer(
            getAddress(chainSelect == ChainSelect.MAINNET ? "mainnet.deployer.create3" : "polygon.deployer.create3")
        );

        //address _deployedAddr = create3Deployer.deployedAddress(byteCode, dev, stringToBytes32("TEST"));

        sliceCore = create3Deployer.deploy(byteCode, stringToBytes32("TEST"));

        // enable slice token creation
        ISliceCore(sliceCore).changeSliceTokenCreationEnabled(true);
        // approve address as Slice token creator
        ISliceCore(sliceCore).changeApprovedSliceTokenCreator(dev, true);
        // set peer address
        IOAppCore(sliceCore).setPeer(
            (chainSelect == ChainSelect.MAINNET ? 30109 : 30101), bytes32(uint256(uint160(sliceCore)))
        );

        tokenAddr = ISliceCore(sliceCore).createSlice("Slice Token", "SC", positions);
    }

    function stringToBytes32(string memory _string) internal pure returns (bytes32 result) {
        require(bytes(_string).length <= 32, "String too long"); // Ensure string length is not greater than 32 bytes

        assembly {
            result := mload(add(_string, 32))
        }
    }

    function isContract(address contractAddress) internal view returns (bool) {
        bytes32 existingCodeHash = contractAddress.codehash;

        // https://eips.ethereum.org/EIPS/eip-1052
        // keccak256('') == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
        return existingCodeHash != bytes32(0)
            && existingCodeHash != 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    }

    /* =========================================================== */
    /*    ==================      setup     ===================    */
    /* =========================================================== */

    function setUp() public {
        forkMainnet(MAINNET_BLOCK_NUMBER);
        forkPolygon(POLYGON_BLOCK_NUMBER);
        selectMainnet();

        usdc = IERC20(getAddress("mainnet.usdc"));
        link = IERC20(getAddress("mainnet.link"));
        weth = IWETH(getAddress("mainnet.weth"));

        wmaticPolygon = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        maxEstimatedPrices.push(maxEstWethPrice);
        maxEstimatedPrices.push(maxEstLinkPrice);

        // mint user some USDC
        deal(address(usdc), address(dev), 1 ether);
        vm.startPrank(dev);

        // create positions
        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            wethUnits // 0.1 wETH
        );

        Position memory linkPosition = Position(
            1, // mainnet
            address(link), // chainlink
            linkUnits // 20 LINK
        );

        positions.push(wethPosition);
        positions.push(linkPosition);

        (address sCore, address sToken) = deployTestContracts(ChainSelect.MAINNET);
        core = SliceCore(payable(sCore));
        token = SliceToken(payable(sToken));

        usdcWethRoute = abi.encodePacked(usdcWethRoute, address(core));
        usdcLinkRoute = abi.encodePacked(usdcLinkRoute, address(core));
        usdcWmaticRoute = abi.encodePacked(usdcWmaticRoute, address(core));

        routes.push(usdcWethRoute);
        routes.push(usdcLinkRoute);

        usdc.approve(address(core), MAX_ESTIMATED_PRICE * 10);
        usdc.approve(address(token), MAX_ESTIMATED_PRICE * 10);

        Position memory ccPos = Position(137, address(wmaticPolygon), wmaticUnits);

        ccPositions.push(ccPos);

        ccRoutes.push(usdcWmaticRoute);

        maxEstCCPrices.push(maxWMaticPrice);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);

        vm.stopPrank();
    }

    /* =========================================================== */
    /*   ==================    createSlice   ==================    */
    /* =========================================================== */
    function test_CreateSlice() public {
        vm.startPrank(dev);
        // approve address as Slice token creator
        core.changeApprovedSliceTokenCreator(users[1], true);

        // call create Slice token from that address
        vm.stopPrank();

        vm.prank(users[1]);

        address sliceTokenAddress = core.createSlice("Test Token", "TT", positions);
        // verify that the Slice token is deployed
        SliceToken deployedSliceToken = SliceToken(sliceTokenAddress);
        assertEq("Test Token", deployedSliceToken.name());
        assertEq("TT", deployedSliceToken.symbol());

        // verify that Slice token works
        Position[] memory slicePositions = deployedSliceToken.getPositions();
        for (uint256 i = 0; i < slicePositions.length; i++) {
            assertEq(positions[i].chainId, slicePositions[i].chainId);
            assertEq(positions[i].token, slicePositions[i].token);
            assertEq(positions[i].units, slicePositions[i].units);
        }

        // verify that Slice token address is registered in the core contract
        bool isSliceRegistered = core.isSliceTokenRegistered(sliceTokenAddress);
        assertEq(true, isSliceRegistered);
    }

    function test_Cannot_CreateSlice_NotAuthorized() public {
        vm.prank(dev);
        core.changeSliceTokenCreationEnabled(true);

        // call create Slice token from an unverified address
        vm.prank(users[2]);
        // verify that transaction fails with the correct revert message
        vm.expectRevert(bytes4(keccak256("UnauthorizedCaller()")));
        core.createSlice("Test Token", "TT", positions);
    }

    function test_Cannot_CreateSlice_CreationNotEnabled() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(false);

        vm.expectRevert(bytes4(keccak256("TokenCreationDisabled()")));
        core.createSlice("Test Token", "TT", positions);
        vm.stopPrank();
    }
    /* =========================================================== */
    /*   ===========   purchaseUnderlyingAssets   =============    */
    /* =========================================================== */

    function test_PurchaseUnderlyingAssets() public {
        deal(address(usdc), dev, 10 ether);

        vm.startPrank(dev);
        // call mint -> call purchase underlying assets
        usdc.approve(address(token), 10 ether);
        usdc.approve(address(core), 10 ether);
        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsProcured(address(token), 1000000000000000000, dev);

        token.mint(1000000000000000000, maxEstimatedPrices, routes);

        // verify that the assets are purhased
        uint256 wethBalance = weth.balanceOf(address(core));
        uint256 linkBalance = link.balanceOf(address(core));

        assertGe(wethBalance, wethUnits);
        assertGe(linkBalance, linkUnits);

        vm.stopPrank();
    }

    function test_PurchaseUnderlyingAssets_CrossChain() public {
        deal(address(usdc), dev, 10 ether);

        vm.startPrank(dev);

        vm.deal(dev, 100 ether);

        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        bytes32 mintID = ccToken.mint(1 ether, maxEstCCPrices, ccRoutes);

        SlicePayloadData memory pd = SlicePayloadData(1, mintID, address(wmaticPolygon), 1 ether, "");

        bytes memory pd_enc = abi.encode(pd);

        makePersistent(address(ccToken));

        (address polygonCore,) = deployTestContracts(ChainSelect.POLYGON);

        selectPolygon();

        deal(polygonCore, 100 ether);

        // don't do actual swap here yet
        deal(address(wmaticPolygon), polygonCore, wmaticUnits);

        IOAppCore(polygonCore).setPeer(30101, bytes32(uint256(uint160(address(core)))));

        vm.stopPrank();

        vm.prank(getAddress("polygon.stargateAdapter"));
        ISliceCore(polygonCore).onPayloadReceive(pd_enc);
        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintID,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: true,
            user: address(0),
            underlying: address(0),
            units: 0
        });

        bytes memory ccsEncoded = abi.encode(ccs);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        // verify that mint is complete
        vm.expectEmit(true, true, true, false);
        emit ISliceCore.UnderlyingAssetsProcured(address(ccToken), 1 ether, dev);

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 tokenBalance = ccToken.balanceOf(dev);
        assertEq(1 ether, tokenBalance);
    }

    function test_Cannot_PurchaseUnderlyingAssets_NotRegistedSliceToken() public {
        // verify that it reverts with the correct revert msg
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        // call purchaseUnderlying from a non-registered address
        core.purchaseUnderlyingAssets(bytes32(0), 1, maxEstimatedPrices, routes);
    }

    function test_Cannot_PurchaseUnderlyingAssets_TokenPriceNotTransferred() public {
        vm.prank(address(token));
        vm.expectRevert(bytes4(keccak256("TokenPriceNotTransferred()")));
        core.purchaseUnderlyingAssets(bytes32(0), 1 ether, maxEstimatedPrices, routes);
    }

    function test_Cannot_PurchaseUnderlyingAssets_InvalidMintId() public {
        deal(address(usdc), address(core), 10 ether);
        vm.prank(address(token));
        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));
        core.purchaseUnderlyingAssets(bytes32(0), 1 ether, maxEstimatedPrices, routes);
    }

    /* =========================================================== */
    /*   ============   collectUnderlyingAssets   =============    */
    /* =========================================================== */
    function test_CollectUnderlyingAssets() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(link), address(dev), linkUnits);

        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);

        vm.expectEmit(true, true, true, false);
        // verify that event is emitted
        emit ISliceCore.UnderlyingAssetsProcured(address(token), 1 ether, dev);

        token.manualMint(1 ether);

        uint256 wethBalance = weth.balanceOf(dev);
        uint256 linkBalance = link.balanceOf(dev);
        assertEq(0, wethBalance);
        assertEq(0, linkBalance);

        uint256 coreWethBalance = weth.balanceOf(address(core));
        uint256 coreLinkBalance = link.balanceOf(address(core));
        assertEq(wethUnits, coreWethBalance);
        assertEq(linkUnits, coreLinkBalance);

        uint256 tokenBalance = token.balanceOf(dev);
        assertEq(1 ether, tokenBalance);

        vm.stopPrank();
    }

    function test_CollectUnderlyingAssets_CrossChain() public {
        deal(address(usdc), dev, 10 ether);

        vm.startPrank(dev);

        vm.deal(dev, 100 ether);

        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        bytes32 mintId = ccToken.manualMint(1 ether);
        assertNotEq(bytes32(0), mintId);

        // prepare cross chain logic
        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MANUAL_MINT,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });

        bytes memory ccsEncoded = abi.encode(ccs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        makePersistent(address(ccToken));

        // change network
        selectPolygon();

        (address polygonCore,) = deployTestContracts(ChainSelect.POLYGON);

        deal(address(wmaticPolygon), dev, wmaticUnits);
        wmaticPolygon.approve(polygonCore, wmaticUnits);

        vm.deal(polygonCore, 100 ether);
        vm.stopPrank();

        // call lzReceive with correct message, value from endpoint address
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        // verify that asset has been transferred from user to core
        uint256 wmaticBalanceUser = wmaticPolygon.balanceOf(dev);
        assertEq(0, wmaticBalanceUser);

        uint256 wmaticBalanceCore = wmaticPolygon.balanceOf(address(polygonCore));
        assertEq(wmaticUnits, wmaticBalanceCore);

        // create cross chain signal
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: true,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });

        bytes memory ccsEncoded2 = abi.encode(_ccsResponse2);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        // verify that mint is complete
        vm.expectEmit(true, true, true, false);
        emit ISliceCore.UnderlyingAssetsProcured(address(ccToken), 1 ether, dev);

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        uint256 tokenBalance = ccToken.balanceOf(dev);
        assertEq(1 ether, tokenBalance);
    }

    function test_Cannot_CollectUnderlyingAssets_NotRegisteredSliceToken() public {
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        core.collectUnderlyingAssets(bytes32(0), 1 ether);
    }

    function test_Cannot_CollectUnderlyingAssets_InvalidMintId() public {
        vm.prank(address(token));

        vm.expectRevert(bytes4(keccak256("MintIdDoesNotExist()")));

        core.collectUnderlyingAssets(bytes32(0), 1 ether);
    }

    function test_Cannot_CollectUnderlyingAssets_LocalAssetTransferFailed_NoFunds() public {
        vm.startPrank(dev);

        weth.approve(address(core), wethUnits);
        link.approve(address(core), linkUnits);

        vm.expectRevert();
        token.manualMint(1 ether);

        vm.stopPrank();
    }

    function test_Cannot_CollectUnderlyingAssets_LocalAssetTransferFailed_NotApproved() public {
        deal(address(weth), address(dev), wethUnits);
        deal(address(weth), address(dev), linkUnits);

        vm.startPrank(dev);

        vm.expectRevert();

        token.manualMint(1 ether);
    }

    /* =========================================================== */
    /*   ==============    redeemUnderlying    ================    */
    /* =========================================================== */
    function test_RedeemUnderlying() public {
        // mint some slice tokens
        vm.startPrank(dev);

        token.mint(1000000000000000000, maxEstimatedPrices, routes);
        uint256 wethTokenbalanceBefore = weth.balanceOf(address(core));
        uint256 linkTokenbalanceBefore = link.balanceOf(address(core));
        // call redeem underlying
        token.redeem(1000000000000000000);

        // verify that the assets are in the user's wallet and gone from the slice token
        uint256 wethBalance = weth.balanceOf(address(dev));
        uint256 linkBalance = link.balanceOf(address(dev));
        assertEq(wethBalance, positions[0].units);
        assertEq(linkBalance, positions[1].units);
        //assertEq(wbtcBalance, positions[1].units);
        //assertEq(linkBalance, positions[2].units);

        uint256 wethTokenbalance = weth.balanceOf(address(core));
        uint256 linkTokenbalance = link.balanceOf(address(core));

        assertEq(wethTokenbalanceBefore - wethTokenbalance, wethUnits);
        assertEq(linkTokenbalanceBefore - linkTokenbalance, linkUnits);

        uint256 sliceBalance = token.balanceOf(address(dev));
        assertEq(0, sliceBalance);
        vm.stopPrank();
    }

    function test_Cannot_RedeemUnderlying_NotAuthorized() public {
        // verify that it reverts with the correct reason
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        // call redeem from not registered slice token
        core.redeemUnderlying(bytes32(0));
    }

    /* =========================================================== */
    /*   ====================    refund    ====================    */
    /* =========================================================== */
    function test_Refund() public {
        // transfer one of the assets to a new account
        deal(address(weth), address(dev), wethUnits);

        // make sure the balance of the other asset is 0
        uint256 balance = link.balanceOf(dev);
        assertEq(balance, 0);
        // approve that 1 asset
        vm.startPrank(dev);
        weth.approve(address(core), wethUnits);

        // make sure that the whole process fails with the correct error
        vm.expectRevert(bytes4(keccak256("LocalAssetTransferFailed()")));

        // make sure that all balances are unchanged
        token.manualMint(1 ether);
    }

    function test_Refund_CrossChain_refundLocal() public {
        bytes32 mintId = _prepareCrossChainRefund();

        address polygonCore = _doFailedMintOnPolygon(mintId);

        // send the response msg
        // create cross chain signal
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });
        bytes memory ccsEncoded2 = abi.encode(_ccsResponse2);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        // expect the mint failed call to slice token here and event emit
        vm.expectEmit(true, true, false, false);
        emit ISliceToken.SliceMintFailed(dev, 1 ether);

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        // make sure that the refund process is set in place
        (address _adrr, uint256 signalsOk, uint256 signalsFailed, uint256 _quantity, address _user) =
            SliceCore(core).transactionCompleteSignals(mintId);

        assertEq(signalsFailed, 1);
        assertEq(signalsOk, 1);

        uint256 wethBalanceBefore = weth.balanceOf(dev);
        assertEq(wethBalanceBefore, 0);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintId);
        bool isStateFailed = txInfo.state == TransactionState.FAILED;
        assertEq(isStateFailed, true);

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.RefundCompleted(dev, 1 ether);
        // do the refund calls
        ccToken.refund(mintId);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo2 = ccToken.getMint(mintId);
        bool isStateRefunded = txInfo2.state == TransactionState.REFUNDED;
        assertEq(isStateRefunded, true);

        uint256 wethBalanceAfter = weth.balanceOf(dev);
        assertEq(wethBalanceAfter, 1 ether);
    }

    function test_Refund_CrossChain_refundRemote() public {
        bytes32 mintId = _prepareCrossChainRefund2();

        address polygonCore = _doFailedMintOnPolygon2(mintId);

        _handleMainnetResponseOnFailedMint(mintId, polygonCore);

        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.REFUND,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });

        bytes memory ccsEncoded4 = abi.encode(_ccsResponse2);

        Origin memory origin2 = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        selectPolygon();
        vm.deal(polygonCore, 100 ether);

        uint256 balanceBefore = wmaticPolygon.balanceOf(dev);
        assertEq(balanceBefore, 0);

        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive(origin2, bytes32(0), ccsEncoded4, dev, bytes(""));

        uint256 balanceAfter = wmaticPolygon.balanceOf(dev);
        assertEq(balanceAfter, wmaticUnits);

        _ccsResponse2.srcChainId = uint32(block.chainid);
        _ccsResponse2.ccsType = CrossChainSignalType.REFUND_COMPLETE;
        _ccsResponse2.success = true;

        bytes memory ccsEncoded5 = abi.encode(_ccsResponse2);

        Origin memory origin3 = Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        selectMainnet();

        vm.expectEmit(true, true, false, false);
        emit ISliceToken.RefundCompleted(dev, 1 ether);

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(origin3, bytes32(0), ccsEncoded5, dev, bytes(""));

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo3 = ccToken.getMint(mintId);
        bool isStateRefunded = txInfo3.state == TransactionState.REFUNDED;
        assertEq(isStateRefunded, true);
    }

    function test_Cannot_Refund_NotSliceToken() public {
        // make sure that refund can only be called by slice token
        SliceTransactionInfo memory _txInfo;
        vm.expectRevert(bytes4(keccak256("UnregisteredSliceToken()")));
        core.refund(_txInfo);
    }

    function test_Cannot_Refund_InvalidState() public {
        // make sure that refund can only be called if state is refunding
        vm.expectRevert(bytes4(keccak256("InvalidTransactionState()")));

        SliceTransactionInfo memory _txInfo = SliceTransactionInfo({
            id: bytes32(0),
            quantity: 1 ether,
            user: dev,
            state: TransactionState.OPEN,
            data: bytes("")
        });

        vm.prank(address(token));
        core.refund(_txInfo);
    }

    function test_Cannot_Refund_NotAllCrossChainSignalsReceived() public {
        // do the cross chain testing logic but do not send 1 of the signals
        bytes32 mintId = _prepareCrossChainRefund();
        address polygonCore = _doFailedMintOnPolygon(mintId);

        selectMainnet();

        vm.prank(address(core));
        ccToken.mintFailed(mintId);

        // make sure it fails with the correct error
        vm.expectRevert(bytes4(keccak256("NotAllCrossChainSignalsReceived()")));
        ccToken.refund(mintId);
    }

    /* =========================================================== */
    /*  =========   changeSliceTokenCreationEnabled   ===========  */
    /* =========================================================== */
    function test_ChangeSliceTokenCreationEnabled() public {
        vm.startPrank(dev);
        // enable slice token creation
        core.changeSliceTokenCreationEnabled(true);

        // verify that we can create slice tokens
        address newSliceToken = core.createSlice("New Test Token", "NTT", positions);
        bool isRegistered = core.isSliceTokenRegistered(newSliceToken);
        assertTrue(isRegistered);

        Position[] memory newTokenPositions = SliceToken(newSliceToken).getPositions();
        for (uint256 i = 0; i < newTokenPositions.length; i++) {
            assertEq(positions[i].chainId, newTokenPositions[i].chainId);
            assertEq(positions[i].token, newTokenPositions[i].token);
            assertEq(positions[i].units, newTokenPositions[i].units);
        }

        // disable slice token creation
        core.changeSliceTokenCreationEnabled(false);

        vm.expectRevert(bytes4(keccak256("TokenCreationDisabled()")));
        // verify that we cannot create slice tokens
        core.createSlice("New Test Token", "NTT", positions);
        vm.stopPrank();
    }

    function test_Cannot_ChangeSliceTokenCreationEnabled_NotAuthorized() public {
        vm.prank(users[2]);
        // verify that it reverts
        vm.expectRevert();
        // try changing enable/disable with non-owner address
        core.changeSliceTokenCreationEnabled(false);
    }

    function _prepareCrossChainRefund() private returns (bytes32 mintId) {
        vm.startPrank(dev);

        Position memory wethPosition = Position(
            1, // mainnet
            address(weth), // wrapped ETH
            1 ether // 0.1 wETH
        );

        ccPositions.push(wethPosition);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);
        weth.approve(address(ccToken), 10 ether);
        weth.approve(address(core), 10 ether);

        // run the cross-chain flow
        deal(address(usdc), dev, 10 ether);
        deal(address(weth), dev, 1 ether);

        vm.deal(dev, 100 ether);

        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        mintId = ccToken.manualMint(1 ether);
        assertNotEq(bytes32(0), mintId);

        vm.stopPrank();
    }

    function _doFailedMintOnPolygon(bytes32 mintId) private returns (address) {
        vm.startPrank(dev);
        // prepare cross chain logic
        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MANUAL_MINT,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });

        bytes memory ccsEncoded = abi.encode(ccs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        makePersistent(address(ccToken));

        // change network
        selectPolygon();

        (address polygonCore,) = deployTestContracts(ChainSelect.POLYGON);

        // make sure that the user has no wmatic on dst chain
        uint256 balance = wmaticPolygon.balanceOf(dev);
        assertEq(0, balance);

        vm.deal(polygonCore, 100 ether);
        vm.stopPrank();

        // send the cross-chain msg: call lzReceive
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));
        // TODO: make sure that it fails correctly
        // handleManualMintSignal => transfer fail => create cross chain signal w success false
        return polygonCore;
    }

    function _prepareCrossChainRefund2() internal returns (bytes32 mintId) {
        vm.startPrank(dev);

        Position memory polygonLinkPosition = Position(
            137, // polygon
            polygonLink, // link
            1 ether
        );

        ccPositions.push(polygonLinkPosition);

        address ccTokenAddr = core.createSlice("CC Slice", "CC", ccPositions);

        ccToken = SliceToken(ccTokenAddr);
        usdc.approve(address(ccToken), MAX_ESTIMATED_PRICE * 10);
        weth.approve(address(ccToken), 10 ether);
        weth.approve(address(core), 10 ether);

        vm.deal(dev, 100 ether);

        (bool success,) = address(core).call{value: 1 ether}("");
        assertTrue(success);

        mintId = ccToken.manualMint(1 ether);
        assertNotEq(bytes32(0), mintId);

        vm.stopPrank();
    }

    function _doFailedMintOnPolygon2(bytes32 mintId) internal returns (address) {
        vm.startPrank(dev);
        // prepare cross chain logic
        CrossChainSignal memory ccs = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MANUAL_MINT,
            success: false,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });

        bytes memory ccsEncoded = abi.encode(ccs);

        Origin memory origin = Origin({srcEid: 30101, sender: bytes32(uint256(uint160(address(core)))), nonce: 1});

        makePersistent(address(ccToken));

        // change network
        selectPolygon();

        (address polygonCore,) = deployTestContracts(ChainSelect.POLYGON);

        deal(address(wmaticPolygon), dev, wmaticUnits);
        wmaticPolygon.approve(polygonCore, wmaticUnits);

        vm.deal(polygonCore, 100 ether);
        vm.stopPrank();

        // call lzReceive with correct message, value from endpoint address
        vm.prank(getAddress("polygon.layerZeroEndpoint"));
        IOAppReceiver(polygonCore).lzReceive(origin, bytes32(0), ccsEncoded, dev, bytes(""));

        uint256 wmaticBalanceCore = wmaticPolygon.balanceOf(address(polygonCore));
        assertEq(wmaticUnits, wmaticBalanceCore);

        return polygonCore;
    }

    function _handleMainnetResponseOnFailedMint(bytes32 mintId, address polygonCore) private {
        CrossChainSignal memory _ccsResponse2 = CrossChainSignal({
            id: mintId,
            srcChainId: uint32(block.chainid),
            ccsType: CrossChainSignalType.MINT,
            success: true,
            user: dev,
            underlying: address(wmaticPolygon),
            units: wmaticUnits
        });
        bytes memory ccsEncoded2 = abi.encode(_ccsResponse2);

        _ccsResponse2.success = false;
        _ccsResponse2.underlying = polygonLink;
        _ccsResponse2.units = 1 ether;
        bytes memory ccsEncoded3 = abi.encode(_ccsResponse2);

        Origin memory originResponse =
            Origin({srcEid: 30109, sender: bytes32(uint256(uint160(address(polygonCore)))), nonce: 1});

        selectMainnet();

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded2, dev, bytes(""));

        vm.prank(getAddress("mainnet.layerZeroEndpoint"));
        IOAppReceiver(core).lzReceive(originResponse, bytes32(0), ccsEncoded3, dev, bytes(""));

        // make sure that the refund process is set in place
        (address _adrr, uint256 signalsOk, uint256 signalsFailed, uint256 _quantity, address _user) =
            SliceCore(core).transactionCompleteSignals(mintId);

        assertEq(signalsFailed, 1);
        assertEq(signalsOk, 1);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo = ccToken.getMint(mintId);
        bool isStateFailed = txInfo.state == TransactionState.FAILED;
        assertEq(isStateFailed, true);

        ccToken.refund(mintId);

        // get the mint info from the slice token
        SliceTransactionInfo memory txInfo2 = ccToken.getMint(mintId);
        bool isStateRefunding = txInfo2.state == TransactionState.REFUNDING;
        assertEq(isStateRefunding, true);
    }
}
