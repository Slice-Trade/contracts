// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OApp, Origin, MessagingFee} from "@lz-oapp-v2/OApp.sol";
import {MessagingParams, MessagingReceipt} from "@lz-oapp-v2/interfaces/ILayerZeroEndpointV2.sol";

import "../external/AggregatorV2V3Interface.sol";

import "./CrossChainVaultStructs.sol";
import {ICrossChainVault} from "./ICrossChainVault.sol";
import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {ISliceToken} from "../interfaces/ISliceToken.sol";
import {IChainInfo} from "../interfaces/IChainInfo.sol";

import {Position, LzMsgGroupInfo, Chain} from "../Structs.sol";
import {TokenAmountUtils} from "../libs/TokenAmountUtils.sol";
import {SliceTokenShareMath} from "./SliceTokenShareMath.sol";
import {LayerZeroUtils} from "../libs/LayerZeroUtils.sol";

contract CrossChainVault is ICrossChainVault, Ownable2Step, ReentrancyGuard, OApp {
    using SafeERC20 for IERC20;

    ISliceCore immutable sliceCore;
    IChainInfo immutable chainInfo;

    bool public isPaused;

    uint256 public MAX_TIMESTAMP_DIFF = 300;

    /**
     * @dev Stores all commitment strategies created in this vault
     */
    mapping(bytes32 strategyId => CommitmentStrategy commitmentStrategy) public commitmentStrategies;
    /**
     * @dev Stores all commitments created in this vault
     */
    mapping(bytes32 commitmentId => Commitment commitment) public commitments;

    /**
     * @dev keccak256(abi.encodePacked(strategyId, userAddress)) to record if user is approved for a strategy
     */
    mapping(bytes32 strategyIdAddressHash => bool approved) public approvedForPrivateStrategy;
    /**
     * @dev Stores all oracle price updates for a given underlying asset token
     */
    mapping(bytes32 strategyIdTokenHash => OraclePriceUpdate) public oraclePriceUpdates;

    /**
     * @dev Stores the amounts committed for each asset for each strategy
     */
    mapping(bytes32 strategyId => mapping(address => uint256) commitedAmounts) public committedAmountsPerStrategy;

    /**
     * @dev Stores cross-chain asset removals, that are sent to LZ but have not been confirmed yet
     */
    mapping(bytes32 strategyId => mapping(address => uint256)) public pendingRemovals;

    /**
     * @dev Stores cross chain gas information for layer zero messages
     */
    mapping(CrossChainVaultSignalType ccsType => uint128 gas) public lzGasLookup;

    /**
     * @dev Stores the chainlink price feed addresses for the given underlying asset token
     */
    mapping(address underlyingAsset => AggregatorV2V3Interface priceFeed) public priceFeedsForAssets;

    /**
     * @dev Nonce for each user to guranatee unique hashes for IDs
     */
    mapping(address => uint256) public nonces;

    modifier vaultNotPaused() {
        if (isPaused) {
            revert VaultIsPaused();
        }
        _;
    }

    constructor(ISliceCore _sliceCore, IChainInfo _chainInfo, address _lzEndpoint, address _owner)
        Ownable(_owner)
        OApp(_lzEndpoint, _owner)
    {
        sliceCore = _sliceCore;
        chainInfo = _chainInfo;

        // TODO: gas estimations
        lzGasLookup[CrossChainVaultSignalType.COMMIT] = 2e5;
        lzGasLookup[CrossChainVaultSignalType.COMMIT_COMPLETE] = 2e5;
        lzGasLookup[CrossChainVaultSignalType.REMOVE] = 2e5;
        lzGasLookup[CrossChainVaultSignalType.REMOVE_COMPLETE] = 2e5;
    }

    /**
     * @dev See ICrossChainVault - createCommitmentStrategy
     */
    function createCommitmentStrategy(address token, uint256 target, bool isPrivate) external vaultNotPaused {
        // check that slice token exists
        bool isValidSlice = sliceCore.isSliceTokenRegistered(token);
        if (!isValidSlice) {
            revert UnregisteredSliceToken();
        }

        _verifyTarget(target);

        // create strategy ID
        uint256 nonce = nonces[msg.sender]++;

        bytes32 strategyId = keccak256(
            abi.encodePacked(
                this.createCommitmentStrategy.selector,
                block.chainid,
                msg.sender,
                address(this),
                token,
                target,
                block.timestamp,
                nonce
            )
        );

        // create strategy
        CommitmentStrategy memory _strategy = CommitmentStrategy({
            id: strategyId,
            creator: msg.sender,
            token: token,
            target: target,
            isPrivate: isPrivate,
            nonce: 0
        });

        // store strategy
        commitmentStrategies[strategyId] = _strategy;

        emit CommitmentStrategyCreated(strategyId);
    }

    /**
     * @dev See ICrossChainVault - modifyCommitmentStrategyTarget
     */
    function modifyCommitmentStrategyTarget(bytes32 strategyId, uint256 newTarget) external vaultNotPaused {
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];
        _verifyStrategyId(strategyId, _strategy);

        if (msg.sender != _strategy.creator) {
            revert Unauthorized();
        }

        _verifyTarget(newTarget);

        // if new target is lower, it can only be lowered to not be less than the already committed amounts
        Position[] memory _positions = ISliceToken(_strategy.token).getPositions();
        uint256 posLength = _positions.length;
        for (uint256 i = 0; i < posLength; i++) {
            uint256 newUnits =
                TokenAmountUtils.calculateAmountOutMin(newTarget, _positions[i].units, _positions[i].decimals);
            if (newUnits < committedAmountsPerStrategy[strategyId][_positions[i].token]) {
                revert NewTargetTooLow();
            }
        }

        commitmentStrategies[strategyId].target = newTarget;

        emit CommitmentStrategyTargetModified(strategyId, newTarget);
    }

    function executeCommitmentStrategy(bytes32 strategyId, uint128[] calldata fees)
        external
        payable
        nonReentrant
        vaultNotPaused
    {
        // get the strategy
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];

        Position[] memory _positions = ISliceToken(_strategy.token).getPositions();
        uint256 _positionsLength = _positions.length;

        // go through each underlying position
        for (uint256 i = 0; i < _positionsLength; i++) {
            // if target committedAmountsPerStrategy for each is > amountOutMin for target and for each
            uint256 targetUnits =
                TokenAmountUtils.calculateAmountOutMin(_strategy.target, _positions[i].units, _positions[i].decimals);
            uint256 committedUnits = committedAmountsPerStrategy[strategyId][_positions[i].token];
            uint256 pendingRemovalUnits = pendingRemovals[strategyId][_positions[i].token];
            if ((committedUnits - pendingRemovalUnits) < targetUnits) {
                revert InvalidAmount();
            }

            // reset all committed units to 0
            committedAmountsPerStrategy[strategyId][_positions[i].token] = 0;

            // get the price for the position
            uint256 latestUSDPrice = getLatestPriceInfo(_positions[i].token);

            uint8 answerDecimals = priceFeedsForAssets[_positions[i].token].decimals();

            OraclePriceUpdate memory _priceUpdate = OraclePriceUpdate({
                id: strategyId,
                token: _positions[i].token,
                decimals: answerDecimals,
                price: latestUSDPrice,
                updateTimestamp: block.timestamp
            });

            // store the oracle price for each underlying asset
            bytes32 strategyIdTokenHash = keccak256(abi.encode(strategyId, _positions[i].token));
            oraclePriceUpdates[strategyIdTokenHash] = _priceUpdate;
        }

        // Increase nonce for commitment strategy
        ++commitmentStrategies[strategyId].nonce;

        ISliceToken(_strategy.token).mint(_strategy.target, fees);
    }

    function commitToStrategy(
        bytes32 strategyId,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint128[] calldata fees
    ) external payable nonReentrant vaultNotPaused {
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];

        _verifyStrategy(strategyId, _strategy);

        // for amount we have to check:
        // - get positions for the slice token
        Position[] memory _positions = ISliceToken(_strategy.token).getPositions();

        // Create cross chain vault signals array to store grouped lz msgs
        CrossChainVaultSignal[] memory ccMsgs = new CrossChainVaultSignal[](assets.length);
        // create LzMsgGroupInfo to store grouping data
        LzMsgGroupInfo memory lzMsgInfo = LzMsgGroupInfo(0, 0, 0, assets.length, msg.value);

        // - loop through the slice token positions:
        // duplicates in the assets[] array will be ignored since we use the slice tokens positions for the loop
        for (uint256 i = 0; i < _positions.length; i++) {
            //      - check if assets array contains the position
            uint256 amountToTransfer = _getAmountToTransfer(strategyId, assets, amounts, _positions[i]);

            if (amountToTransfer == 0) {
                continue;
            }

            //      - if it is local, transfer funds from user to vault, create commitment struct, save it, modify storage to store other details
            if (_isPositionLocal(_positions[i])) {
                IERC20(_positions[i].token).safeTransferFrom(msg.sender, address(this), amountToTransfer);
                // approve SliceCore to spend these tokens (for minting later in executeStrategy)
                IERC20(_positions[i].token).approve(address(sliceCore), amountToTransfer);
                // record the commitment
                bytes32 commitmentId = _updateCommitment(
                    strategyId, msg.sender, amountToTransfer, _positions[i].token, _positions[i].decimals, block.chainid
                );
                emit CommittedToStrategy(strategyId, commitmentId);
            } else {
                // create cross-chain vault signal to send to vault on other chain
                CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
                    id: strategyId,
                    srcChainId: uint32(block.chainid),
                    ccvsType: CrossChainVaultSignalType.COMMIT,
                    user: msg.sender,
                    underlying: _positions[i].token,
                    decimals: _positions[i].decimals,
                    amount: amountToTransfer,
                    value: 0
                });
                //      - if it is non-local use the same group LZ message logic as for the SliceCore
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, _positions[i], lzMsgInfo, fees);
            }
        }

        //      - send cross chain messages as needed
        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsg(ccMsgs, ccMsgs[0], lzMsgInfo, fees, msg.sender);
        }
    }

    function removeCommitmentFromStrategy(bytes32 commitmentId, uint256 amount, uint128 fee)
        external
        payable
        nonReentrant
    {
        Commitment memory _commitment = commitments[commitmentId];

        // check that commitment ID exists
        if (commitmentId == bytes32(0) || commitmentId != _commitment.id) {
            revert InvalidCommitmentId();
        }

        // check that msg sender is commitment creator
        if (_commitment.creator != msg.sender) {
            revert Unauthorized();
        }

        // Check the commitment nonce and revert if it is less then current strategy nonce
        if (commitmentStrategies[_commitment.strategyId].nonce != _commitment.strategyNonce) {
            revert StrategyAlreadyExecuted();
        }

        // check that amount has not been consumed yet
        if (_commitment.committed < amount) {
            revert InvalidAmount();
        }

        bool _isCommitmentLocal = _commitment.chainId == block.chainid;

        // send the asset to the user if local
        if (_isCommitmentLocal) {
            IERC20(_commitment.asset).safeTransfer(_commitment.creator, amount);
            // update the committed amount to the new amount
            commitments[commitmentId].committed -= amount;
            committedAmountsPerStrategy[_commitment.strategyId][_commitment.asset] -= amount;

            emit RemovedCommitmentFromStrategy(_commitment.id, amount);
        } else {
            CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
                id: _commitment.id,
                srcChainId: uint32(block.chainid),
                ccvsType: CrossChainVaultSignalType.REMOVE,
                user: _commitment.creator,
                underlying: _commitment.asset,
                decimals: _commitment.decimals,
                amount: amount,
                value: fee
            });
            // send cross chain msg if not local
            CrossChainVaultSignal[] memory ccsMsgs = new CrossChainVaultSignal[](1);
            ccsMsgs[0] = ccs;
            bytes memory ccsEncoded = abi.encode(ccsMsgs);
            // update pending removals, this will prevent execution while the removal is pending becuase the amount will be less
            pendingRemovals[_commitment.strategyId][_commitment.asset] += amount;
            // send the cross-chain message
            _sendLzMsg(CrossChainVaultSignalType.REMOVE, ccsEncoded, uint32(block.chainid), msg.sender);
        }
    }

    function pullMintedTokenShares(bytes32 strategyId, uint256 nonce) external nonReentrant {
        // get the given strategy
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];
        if (_strategy.id == bytes32(0) || _strategy.id != strategyId) {
            revert InvalidStrategyId();
        }

        // check the strategy nonce, if current revert
        if (nonce >= _strategy.nonce) {
            revert StrategyNotExecuted();
        }
        Position[] memory _positions = ISliceToken(_strategy.token).getPositions();
        uint256 posLength = _positions.length;

        // we need usder commitment[] array for TUC_usd
        Commitment[] memory userComms = new Commitment[](posLength);

        // we need position[] array and priceUpdate[] array for TS_usd
        OraclePriceUpdate[] memory priceUpdates = new OraclePriceUpdate[](posLength);

        for (uint256 i = 0; i < posLength; i++) {
            bytes32 commitmentId = keccak256(
                abi.encodePacked(this.commitToStrategy.selector, strategyId, msg.sender, _positions[i].token, nonce)
            );
            // get commitment
            Commitment memory _comm = commitments[commitmentId];
            if (_comm.commitmentState == CommitmentState.PULLED) {
                revert MintedTokenShareAlreadyPulled();
            }
            userComms[i] = _comm;

            // get the oracle price for the asset
            OraclePriceUpdate memory _price = oraclePriceUpdates[keccak256(abi.encode(strategyId, _positions[i].token))];
            priceUpdates[i] = _price;

            // update commitment state to pulled
            commitments[commitmentId].commitmentState = CommitmentState.PULLED;
        }

        // calculate the user slice token share using these values and slice token math
        uint256 TS_usd = SliceTokenShareMath.calcSliceTokenUSDValue(_positions, priceUpdates);

        // we need sMinted (_strategy.target) and TS_usd for TSV_usd
        uint256 TSV_usd = SliceTokenShareMath.calcTotalMintedSliceUSDValue(TS_usd, _strategy.target);

        // we need TUC_usd and TSV_usd for USS
        uint256 TUC_usd = SliceTokenShareMath.calcUserCommsTotalValue(userComms, priceUpdates);

        // tuc / tsv
        uint256 USS = SliceTokenShareMath.calcUserTokenShare(TUC_usd, TSV_usd);

        // uss * sMinted
        uint256 USA = SliceTokenShareMath.calcAmountOfTokensReceiveable(USS, _strategy.target);

        // user them to calculate the user's share of the given mint
        ISliceToken(_strategy.token).transfer(msg.sender, USA);
    }

    function commitmentExists(bytes32 commitmentId) internal view returns (bool) {
        if (commitmentId == bytes32(0)) {
            return false;
        }
        return commitments[commitmentId].id == commitmentId;
    }

    /**
     * @dev See ICrossChainVault - changeUserApprovalToCommitmentStrategy
     */
    function changeUserApprovalToCommitmentStrategy(bytes32 strategyId, address user, bool isApproved)
        external
        vaultNotPaused
    {
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];
        _verifyStrategyId(strategyId, _strategy);

        if (msg.sender != _strategy.creator) {
            revert Unauthorized();
        }

        if (!_strategy.isPrivate) {
            revert StrategyNotPrivate();
        }

        bytes32 strategyIdAddressHash = keccak256(abi.encode(strategyId, user));
        approvedForPrivateStrategy[strategyIdAddressHash] = isApproved;

        emit ChangedUserApprovalToCommitmentStrategy(strategyId, user, isApproved);
    }

    function pauseVault() external onlyOwner vaultNotPaused {
        isPaused = true;
    }

    function restartVault() external onlyOwner {
        if (!isPaused) {
            revert VaultNotPaused();
        }
        isPaused = false;
    }

    function setLzBaseGas(CrossChainVaultSignalType ccsType, uint128 gas) external onlyOwner {
        lzGasLookup[ccsType] = gas;
        emit SetLzBaseGas(ccsType, gas);
    }

    /**
     * @dev This is a work around to allow using SafeERC20.safeTransferFrom in a try/catch block
     * This is needed because internal functions can not be used in a try/catch block
     * More context here: https://ethereum.stackexchange.com/questions/148855/how-can-we-use-safetransferfrom-function-in-a-try-catch-block
     */
    function attemptTransfer(address token, address from, address to, uint256 amount) external {
        if (msg.sender != address(this)) revert("Only slice core can call");
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function setPriceFeedForAsset(address _underlyingAsset, AggregatorV2V3Interface _priceFeed) external onlyOwner {
        priceFeedsForAssets[_underlyingAsset] = _priceFeed;
    }

    function getLatestPriceInfo(address underlyingAsset) internal view returns (uint256) {
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            uint256 timeStamp,
            /*uint80 answeredInRound*/
        ) = priceFeedsForAssets[underlyingAsset].latestRoundData();

        if (block.timestamp - timeStamp > MAX_TIMESTAMP_DIFF) {
            revert StalePrice();
        }

        if (answer < 0) {
            revert InvalidPrice();
        }

        return uint256(answer);
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32, /* _guid */ // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address, /* _executor */ // the Executor address.
        bytes calldata /* _extraData */ // arbitrary data appended by the Executor
    ) internal override {
        if (address(uint160(uint256(_origin.sender))) != address(this)) {
            revert OriginNotVault();
        }

        CrossChainVaultSignal[] memory ccs = abi.decode(payload, (CrossChainVaultSignal[]));

        require(msg.value >= ccs[0].value, "Not enough msg value provided");

        CrossChainVaultSignalType ccsType = ccs[0].ccvsType;

        if (ccsType == CrossChainVaultSignalType.COMMIT) {
            handleCommitSignal(ccs);
        } else if (ccsType == CrossChainVaultSignalType.COMMIT_COMPLETE) {
            handleCommitCompleteSignal(ccs);
        } else if (ccsType == CrossChainVaultSignalType.REMOVE) {
            handleRemoveSignal(ccs);
        } else if (ccsType == CrossChainVaultSignalType.REMOVE_COMPLETE) {
            handleRemoveCompleteSignal(ccs);
        }
    }

    function handleCommitSignal(CrossChainVaultSignal[] memory ccs) internal {
        uint256 ccsLength = ccs.length;
        CrossChainVaultSignal[] memory ccsResponses = new CrossChainVaultSignal[](ccsLength);
        uint256 respMsgCount;

        for (uint256 i = 0; i < ccsLength; i++) {
            try this.attemptTransfer(ccs[i].underlying, ccs[i].user, address(this), ccs[i].amount) {}
            catch {
                continue;
            }

            // approve SliceCore to spend these tokens (for minting later in executeStrategy)
            IERC20(ccs[i].underlying).approve(address(sliceCore), ccs[i].amount);

            CrossChainVaultSignal memory _ccsResponse = CrossChainVaultSignal({
                id: ccs[i].id,
                srcChainId: uint32(block.chainid),
                ccvsType: CrossChainVaultSignalType.COMMIT_COMPLETE,
                user: ccs[i].user,
                underlying: ccs[i].underlying,
                decimals: ccs[i].decimals,
                amount: ccs[i].amount,
                value: 0
            });

            ccsResponses[i] = _ccsResponse;
            ++respMsgCount;
        }
        // Reset the resp array length to the actual length
        assembly {
            mstore(ccsResponses, respMsgCount)
        }
        bytes memory ccsEncoded = abi.encode(ccsResponses);
        _sendLzMsg(CrossChainVaultSignalType.COMMIT_COMPLETE, ccsEncoded, ccs[0].srcChainId, ccs[0].user);
    }

    function handleCommitCompleteSignal(CrossChainVaultSignal[] memory ccs) internal {
        // go through each signal
        uint256 ccsLength = ccs.length;
        for (uint256 i = 0; i < ccsLength; i++) {
            // update commitment for user
            bytes32 commitmentId = _updateCommitment(
                ccs[i].id, ccs[i].user, ccs[i].amount, ccs[i].underlying, ccs[i].decimals, ccs[i].srcChainId
            );
            emit CommittedToStrategy(ccs[i].id, commitmentId);
        }
    }

    function handleRemoveSignal(CrossChainVaultSignal[] memory ccs) internal {
        CrossChainVaultSignal[] memory ccsResponses = new CrossChainVaultSignal[](1);

        IERC20(ccs[0].underlying).safeTransfer(ccs[0].user, ccs[0].amount);

        CrossChainVaultSignal memory _ccsResponse = CrossChainVaultSignal({
            id: ccs[0].id,
            srcChainId: uint32(block.chainid),
            ccvsType: CrossChainVaultSignalType.REMOVE_COMPLETE,
            user: ccs[0].user,
            underlying: ccs[0].underlying,
            decimals: ccs[0].decimals,
            amount: ccs[0].amount,
            value: 0
        });
        ccsResponses[0] = _ccsResponse;
        bytes memory ccsEncoded = abi.encode(ccsResponses);
        _sendLzMsg(CrossChainVaultSignalType.REMOVE_COMPLETE, ccsEncoded, ccs[0].srcChainId, ccs[0].user);
    }

    function handleRemoveCompleteSignal(CrossChainVaultSignal[] memory ccs) internal {
        CrossChainVaultSignal memory _ccs = ccs[0];

        Commitment memory _commitment = commitments[_ccs.id];

        commitments[_ccs.id].committed -= _ccs.amount;

        committedAmountsPerStrategy[_commitment.strategyId][_commitment.asset] -= _ccs.amount;

        pendingRemovals[_commitment.strategyId][_commitment.asset] -= _ccs.amount;

        emit RemovedCommitmentFromStrategy(_commitment.id, _ccs.amount);
    }

    function groupAndSendLzMsg(
        CrossChainVaultSignal[] memory ccMsgs,
        CrossChainVaultSignal memory ccs,
        Position memory position,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees
    ) internal returns (CrossChainVaultSignal[] memory, LzMsgGroupInfo memory) {
        if (lzMsgInfo.currentChainId == position.chainId) {
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            ++lzMsgInfo.currentCount;
        } else {
            if (lzMsgInfo.currentChainId != 0) {
                (ccMsgs, lzMsgInfo) = _sendGroupedLzMsg(ccMsgs, ccs, lzMsgInfo, fees, address(this));

                lzMsgInfo.currentCount = 0;
                lzMsgInfo.currentChainId = position.chainId;
                ccMsgs = new CrossChainVaultSignal[](lzMsgInfo.positionsLength);
            }
            ccMsgs[lzMsgInfo.currentCount] = ccs;
            lzMsgInfo.currentChainId = position.chainId;
            ++lzMsgInfo.currentCount;
        }
        return (ccMsgs, lzMsgInfo);
    }

    function _sendGroupedLzMsg(
        CrossChainVaultSignal[] memory ccMsgs,
        CrossChainVaultSignal memory ccs,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees,
        address refundAddress
    ) private returns (CrossChainVaultSignal[] memory, LzMsgGroupInfo memory) {
        {
            uint256 currentCount = lzMsgInfo.currentCount;
            assembly {
                mstore(ccMsgs, currentCount)
            }
        }
        ccMsgs[0].value = fees[lzMsgInfo.totalMsgCount];
        bytes memory ccsMsgsEncoded = abi.encode(ccMsgs);
        Chain memory dstChain = chainInfo.getChainInfo(lzMsgInfo.currentChainId);

        bytes memory _lzSendOpts = LayerZeroUtils.createLzSendOpts({
            _gas: requiredGas(ccs.ccvsType, uint128(lzMsgInfo.currentCount)),
            _value: fees[lzMsgInfo.totalMsgCount]
        });

        MessagingReceipt memory receipt = _lzSend(
            dstChain.lzEndpointId, ccsMsgsEncoded, _lzSendOpts, MessagingFee(lzMsgInfo.providedFee, 0), refundAddress
        );
        ++lzMsgInfo.totalMsgCount;
        lzMsgInfo.providedFee -= receipt.fee.nativeFee;

        return (ccMsgs, lzMsgInfo);
    }

    function _sendLzMsg(
        CrossChainVaultSignalType ccsType,
        bytes memory ccsEncoded,
        uint32 srcChainId,
        address refundAddress
    ) private {
        bytes memory _lzSendOpts = LayerZeroUtils.createLzSendOpts({_gas: lzGasLookup[ccsType], _value: 0});

        Chain memory srcChain = chainInfo.getChainInfo(srcChainId);

        _lzSend(srcChain.lzEndpointId, ccsEncoded, _lzSendOpts, MessagingFee(msg.value, 0), refundAddress);
    }

    function _getAmountToTransfer(
        bytes32 strategyId,
        address[] calldata assets,
        uint256[] calldata amounts,
        Position memory position
    ) private view returns (uint256) {
        //      - check if assets array contains the position
        int256 assetIdx = _isAssetCommitted(position.token, assets);
        if (assetIdx == -1) {
            return 0;
        }

        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];
        uint256 amountToTransfer = amounts[uint256(assetIdx)];

        uint256 amountNeeded = TokenAmountUtils.calculateAmountOutMin(
            _strategy.target, position.units, position.decimals
        ) - committedAmountsPerStrategy[strategyId][position.token];

        if (amountToTransfer > amountNeeded) {
            amountToTransfer = amountNeeded;
        }

        return amountToTransfer;
    }

    function _updateCommitment(
        bytes32 strategyId,
        address user,
        uint256 amountToTransfer,
        address underlyingAsset,
        uint8 decimals,
        uint256 chainId
    ) private returns (bytes32 commitmentId) {
        uint256 _strategyNonce = commitmentStrategies[strategyId].nonce;
        commitmentId = keccak256(
            abi.encodePacked(this.commitToStrategy.selector, strategyId, user, underlyingAsset, _strategyNonce)
        );

        if (commitmentExists(commitmentId)) {
            commitments[commitmentId].committed += amountToTransfer;
        } else {
            // update commitments
            Commitment memory _commitment = Commitment({
                id: commitmentId,
                strategyId: strategyId,
                commitmentState: CommitmentState.COMMITTED,
                creator: user,
                chainId: chainId,
                asset: underlyingAsset,
                decimals: decimals,
                committed: amountToTransfer,
                strategyNonce: _strategyNonce
            });
            commitments[commitmentId] = _commitment;
        }

        // update committedAmountsPerStrategy
        committedAmountsPerStrategy[strategyId][underlyingAsset] += amountToTransfer;
    }

    function requiredGas(CrossChainVaultSignalType ccsType, uint128 msgsLength) internal view returns (uint128) {
        uint128 _baseGas = lzGasLookup[ccsType];
        uint128 _gasStep = gasStep(ccsType);

        uint128 gasRequired = _baseGas + (_gasStep * msgsLength);

        return gasRequired;
    }

    function gasStep(CrossChainVaultSignalType ccsType) internal pure returns (uint128) {
        // TODO: Gas estimations
        if (ccsType == CrossChainVaultSignalType.COMMIT || ccsType == CrossChainVaultSignalType.COMMIT_COMPLETE) {
            return 55_000;
        }
        return 37_000;
    }

    function _verifyStrategy(bytes32 strategyId, CommitmentStrategy memory _strategy) private view {
        // check that strategy exists
        _verifyStrategyId(strategyId, _strategy);

        // if private check that user is allowed to commit
        if (_strategy.isPrivate) {
            bytes32 strategyIdAddressHash = keccak256(abi.encode(strategyId, msg.sender));
            if (!approvedForPrivateStrategy[strategyIdAddressHash]) {
                revert Unauthorized();
            }
        }
    }

    function _verifyStrategyId(bytes32 strategyId, CommitmentStrategy memory _strategy) private pure {
        if (strategyId == bytes32(0) || strategyId != _strategy.id) {
            revert InvalidStrategyId();
        }
    }

    function _verifyTarget(uint256 target) private pure {
        // if type is amount check that > 0
        if (target == 0) {
            revert InvalidAmount();
        }
    }

    function _verifyAmountToTransferForAsset(
        uint256 amountToTransfer,
        CommitmentStrategy memory _strategy,
        Position memory _position
    ) private view returns (uint256) {
        //      - if yes check how much has been committed
        uint256 alreadyCommitted = committedAmountsPerStrategy[_strategy.id][_position.token];

        //      - calculate total target amount required for asset: target * position units
        uint256 targetAmountForAsset =
            TokenAmountUtils.calculateAmountOutMin(_strategy.target, _position.units, _position.decimals);

        //      - use these to get how much is still missing
        uint256 amountStillNeeded = targetAmountForAsset - alreadyCommitted;

        if (amountStillNeeded == 0) {
            return 0;
        } else if (amountToTransfer > amountStillNeeded) {
            //      - if the user is commiting more then missing, change the amount to the total missing
            amountToTransfer = amountStillNeeded;
        }
        return amountToTransfer;
    }

    function _isAssetCommitted(address asset, address[] memory assets) private pure returns (int256) {
        uint256 len = assets.length;
        for (uint256 i = 0; i < len; i++) {
            if (assets[i] == asset) {
                return int256(i);
            }
        }
        return -1;
    }

    function _isPositionLocal(Position memory position) private view returns (bool) {
        return position.chainId == block.chainid;
    }

    /* =========================================================== */
    /*    ================    OWNABLE2STEP    ==================   */
    /* =========================================================== */
    /**
     * @dev This must be overriden because OApp uses Ownable without 2 step. SliceCore uses Ownable2Step everywhere.
     */
    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    /**
     * @dev This must be overriden because OApp uses Ownable without 2 step. SliceCore uses Ownable2Step everywhere.
     */
    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }

    /* =========================================================== */
    /*    =================    OAPP LZSEND    ==================   */
    /* =========================================================== */
    /// @dev Batch send requires overriding this function from OAppSender because the msg.value contains multiple fees
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    /// @dev Receive is required for LayerZero to refund the fee when the contract is batch sending messages
    receive() external payable {}
}
