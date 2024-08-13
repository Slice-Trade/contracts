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
import {LayerZeroUtils} from "../libs/LayerZeroUtils.sol";

/* 
there is a potential problem: with timestamp based commitments, there is a DoS possibility, 
users can overload the system by submitting a bunch of super small commitments, filling up the commitments & commitmentsForStrategy arrays
if anyone tries to execute the strategy it will be really expensive because it will loop through all the elements in the array

yeah, probably this is not a problem after all because:
- we will only need to calculate the share for each user at pull share / remove commitment

then the costs for the micro comitments will be born by the user who did the micro commitments, so there's no point in doing that for them

how to calculate token share for a user?
Total Slice Price USD / Total User Commitment USD val

--> how to get the total USD Commitment Val?
if we dont store commitment IDs per user per strategy, we bascially have to loop through all commitment ids for a given strategy, check where creator == msg.sender
here we bump into a DoS issue again, namely that if the array is very long it can make it hard for users to withdraw their shares

if we store in a mapping strategyIdAddressHash => bytes32[] commitmentIds we might be better off
and we might not even need to store the commitmentsPerStrategy array, since we probably wont use it anywhere else 

SO:
loop through userCommitmentsForStrategy:
    commitment.committed * commitment.asset.latestRoundData

This is all OK for amount target based commitments, and also works for timestamp target: we can reconstruct how much was minted, and then do the calculation based on that value
, i.e. if there are any leftovers we can calculate becuase we know always the values

what to do in the case of time interval based commitments? 

Namely, how can we always prevent double spending of committed amounts? how can we update consumed in a way that doesn't lead to DoS and is secure when pulling shares and executing

We might need extra mappings and structs for properly accounting for time interval commitments... TODO: Work this out
 */
contract CrossChainVault is ICrossChainVault, Ownable2Step, ReentrancyGuard, OApp {
    using SafeERC20 for IERC20;

    ISliceCore immutable sliceCore;
    IChainInfo immutable chainInfo;

    uint256 constant MIN_TIME_INTERVAL = 3600;

    uint256 public MAX_TIMESTAMP_DIFF = 300; // max timestamp difference between current timestamp and last updated date

    bool public isPaused;

    /**
     * @dev Stores all commitment strategies created in this vault
     */
    mapping(bytes32 strategyId => CommitmentStrategy commitmentStrategy) public commitmentStrategies;
    /**
     * @dev Stores all commitments created in this vault
     */
    mapping(bytes32 commitmentId => Commitment commitment) public commitments;

    /**
     * @dev Stores all commitments for a given user for a given commitment strategy
     */
    mapping(bytes32 strategyIdAddressHash => bytes32[] commitmentIds) public userCommitmentsForStrategy;
    /**
     * @dev keccak256(abi.encodePacked(strategyId, userAddress)) to record if user is approved for a strategy
     */
    mapping(bytes32 strategyIdAddressHash => bool approved) public approvedForPrivateStrategy;
    /**
     * @dev Stores all oracle price updates for a given underlying asset token
     */
    mapping(bytes32 strategyIdTokenHash => OraclePriceUpdate) public oraclePriceUpdates;
    /**
     * @dev keccak256(abi.encodePacked(strategyId, userAddress)) to record a user's slice token share from a given strategy
     */
    mapping(bytes32 strategyIdAddressHash => SliceTokenShare) public sliceTokenShares; // q - We might not even need to store this either...?

    /**
     * @dev Stores the amounts committed for each asset for each strategy
     */
    mapping(bytes32 strategyId => mapping(address => uint256) commitedAmounts) public committedAmountsPerStrategy;

    /**
     * @dev Nonce for each user to guranatee unique hashes for IDs
     */
    mapping(address => uint256) public nonces;

    /**
     * @dev Stores cross chain gas information for layer zero messages
     */
    mapping(CrossChainVaultSignalType ccsType => uint128 gas) public lzGasLookup;

    mapping(address underlyingAsset => AggregatorV2V3Interface priceFeed) public priceFeedsForAssets;

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
    function createCommitmentStrategy(
        address token,
        uint256 target,
        CommitmentStrategyType strategyType,
        bool isPrivate
    ) external vaultNotPaused {
        // check that slice token exists
        bool isValidSlice = sliceCore.isSliceTokenRegistered(token);
        if (!isValidSlice) {
            revert UnregisteredSliceToken();
        }

        _verifyTarget(strategyType, target);

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
            strategyType: strategyType,
            strategyState: CommitmentStrategyState.OPEN,
            creator: msg.sender,
            token: token,
            target: target,
            isPrivate: isPrivate
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

        if (_strategy.strategyState != CommitmentStrategyState.OPEN) {
            revert InvalidStrategyState();
        }

        _verifyTarget(_strategy.strategyType, newTarget);

        commitmentStrategies[strategyId].target = newTarget;

        emit CommitmentStrategyTargetModified(strategyId, newTarget);
    }

    function executeCommitmentStrategy(bytes32 strategyId, uint128[] calldata fees) external payable nonReentrant vaultNotPaused {
        // get the strategy
        CommitmentStrategy memory _strategy = commitmentStrategies[strategyId];

        // check that it is executable
        if (_strategy.strategyState != CommitmentStrategyState.OPEN) {
            revert InvalidStrategyState();
        }

        Position[] memory _positions = ISliceToken(_strategy.token).getPositions();
        uint256 _positionsLength = _positions.length;

        uint256 amountToMint = type(uint256).max;

        // go through each underlying position
        for (uint256 i = 0; i < _positionsLength; i++) {
            // if target committedAmountsPerStrategy for each is > amountOutMin for target and for each
            if (_strategy.strategyType == CommitmentStrategyType.AMOUNT_TARGET) {
                uint256 targetUnits = TokenAmountUtils.calculateAmountOutMin(
                    _strategy.target, _positions[i].units, _positions[i].decimals
                );
                uint256 committedUnits = committedAmountsPerStrategy[strategyId][_positions[i].token];
                if (committedUnits < targetUnits) {
                    revert InvalidAmount();
                }
            }

            // verify that execution is possible for timestamp
            if (_strategy.strategyType == CommitmentStrategyType.TIMESTAMP_TARGET) {
                if (block.timestamp < _strategy.target) {
                    revert InvalidTimestamp();
                }

                uint256 committedUnits = committedAmountsPerStrategy[strategyId][_positions[i].token];
                uint256 amountMintable = TokenAmountUtils.calculateAmountInMin(committedUnits, _positions[i].units, _positions[i].decimals);
                if (amountMintable < amountToMint) {
                    amountToMint = amountMintable;
                }
            }

            // TODO: Verify time interval target

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

        if (_strategy.strategyType == CommitmentStrategyType.AMOUNT_TARGET) {
            ISliceToken(_strategy.token).mint(_strategy.target, fees);
        } else if (_strategy.strategyType == CommitmentStrategyType.TIMESTAMP_TARGET && amountToMint != type(uint256).max) {
            ISliceToken(_strategy.token).mint(amountToMint, fees);
        }
        
        // TODO: execute SliceToken(token).mint for TIME INTERVAL TARGET
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
            uint256 amountToTransfer = _getAmountToTransfer(assets, amounts, _positions[i]);

            if (_strategy.strategyType == CommitmentStrategyType.AMOUNT_TARGET) {
                amountToTransfer = _verifyAmountToTransferForAsset(amountToTransfer, _strategy, _positions[i]);
            }
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

        // check that amount has not been consumed yet
        uint256 availableToRemove = _commitment.committed - _commitment.consumed;
        if (availableToRemove < amount) {
            revert InvalidAmount();
        }

        // check that strategy state is open
        if (commitmentStrategies[_commitment.strategyId].strategyState != CommitmentStrategyState.OPEN) {
            revert StrategyOver();
        }

        bool _isCommitmentLocal = _commitment.chainId == block.chainid;

        // send the asset to the user if local
        if (_isCommitmentLocal) {
            IERC20(_commitment.asset).safeTransfer(_commitment.creator, amount);
            // update the committed amount to the new amount
            commitments[commitmentId].committed = _commitment.committed - amount;
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
            _sendLzMsg(CrossChainVaultSignalType.REMOVE, ccsEncoded, uint32(block.chainid), msg.sender);
        }

        // q - do we allow users to remove their commitments if the target has been reached, but strategy has not yet been executed??
        // we should allow it, because in the execute transaction we will check anyway
    }

    function pullMintedTokenShares(bytes32 strategyId) external nonReentrant {
        // TODO
        // get the oracle price updates for the given strategy & for the provided units

        // get all the commitments for the given strategy

        // calculate the shares for each user

        // user them to calculate the user's share of the given mint

        //
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

        if (_strategy.strategyState != CommitmentStrategyState.OPEN) {
            revert InvalidStrategyState();
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

    /*     function numberOfCommitmentsForStrategy(bytes32 strategyId) external view returns (uint256) {
        return commitmentsForStrategy[strategyId].length;
    } */

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

        commitments[_ccs.id].committed = _commitment.committed - _ccs.amount;

        committedAmountsPerStrategy[_commitment.strategyId][_commitment.asset] -= _ccs.amount;

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

    function _getAmountToTransfer(address[] calldata assets, uint256[] calldata amounts, Position memory position)
        private
        pure
        returns (uint256)
    {
        //      - check if assets array contains the position
        int256 assetIdx = _isAssetCommitted(position.token, assets);
        if (assetIdx == -1) {
            return 0;
        }

        return amounts[uint256(assetIdx)];
    }

    function _updateCommitment(
        bytes32 strategyId,
        address user,
        uint256 amountToTransfer,
        address underlyingAsset,
        uint8 decimals,
        uint256 chainId
    ) private returns (bytes32 commitmentId) {
        uint256 nonce = nonces[user]++;
        commitmentId = keccak256(
            abi.encodePacked(
                this.commitToStrategy.selector,
                chainId,
                user,
                address(this),
                strategyId,
                underlyingAsset,
                block.timestamp,
                nonce
            )
        );

        // update commitments
        Commitment memory _commitment = Commitment({
            id: commitmentId,
            strategyId: strategyId,
            creator: user,
            chainId: chainId,
            asset: underlyingAsset,
            decimals: decimals,
            committed: amountToTransfer,
            consumed: 0
        });
        commitments[commitmentId] = _commitment;

        bytes32 strategyIdAddressHash = keccak256(abi.encode(strategyId, user));
        userCommitmentsForStrategy[strategyIdAddressHash].push(commitmentId);

        // update committedAmountsPerStrategy
        committedAmountsPerStrategy[strategyId][underlyingAsset] += amountToTransfer;
    }

    // calculates TUCUsd
    function calcUserCommsTotalValue(Commitment[] memory _userCommitmentsForStrat) internal view returns (uint256) {
        uint256 commLength = _userCommitmentsForStrat.length;
        uint256 totalUserCommVal;

        for (uint256 i = 0; i < commLength; i++) {
            bytes32 strategyIdTokenHash =
                keccak256(abi.encode(_userCommitmentsForStrat[i].strategyId, _userCommitmentsForStrat[i].asset));
            OraclePriceUpdate memory _priceUpdate = oraclePriceUpdates[strategyIdTokenHash];
            uint256 scaledPrice = _priceUpdate.price * (10 ** _userCommitmentsForStrat[i].decimals);

            // TODO: Should this be consumed?
            uint256 usdValue = (_userCommitmentsForStrat[i].committed * scaledPrice)
                / (10 ** (_userCommitmentsForStrat[i].decimals + _priceUpdate.decimals));

            totalUserCommVal += usdValue;
        }

        return totalUserCommVal;
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

        // check that strategy state is open
        if (_strategy.strategyState != CommitmentStrategyState.OPEN) {
            revert InvalidStrategyState();
        }

        // if private check that user is allowed to commit
        if (_strategy.isPrivate) {
            bytes32 strategyIdAddressHash = keccak256(abi.encode(strategyId, msg.sender));
            if (!approvedForPrivateStrategy[strategyIdAddressHash]) {
                revert Unauthorized();
            }
        }

        // if timestamp target we simply check that timestamp is bigger than current timestamp
        if (_strategy.strategyType == CommitmentStrategyType.TIMESTAMP_TARGET && block.timestamp >= _strategy.target) {
            revert StrategyOver();
        }
        // if it is a recurring time interval users can commit anytime so we don't check
    }

    function _verifyStrategyId(bytes32 strategyId, CommitmentStrategy memory _strategy) private pure {
        if (strategyId == bytes32(0) || strategyId != _strategy.id) {
            revert InvalidStrategyId();
        }
    }

    function _verifyTarget(CommitmentStrategyType strategyType, uint256 target) private view {
        // if type is amount check that > 0
        if (strategyType == CommitmentStrategyType.AMOUNT_TARGET && target == 0) {
            revert InvalidAmount();
        }

        // if type is tstamp check that target is in the future
        if (strategyType == CommitmentStrategyType.TIMESTAMP_TARGET && target <= block.timestamp) {
            revert InvalidTimestamp();
        }

        // if type is time interval check that interval is >= of min
        if (strategyType == CommitmentStrategyType.TIME_INTERVAL_TARGET && target < MIN_TIME_INTERVAL) {
            revert InvalidTimeInterval();
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
