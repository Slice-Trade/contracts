// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./CrossChainVaultStructs.sol";
import {ICrossChainVault} from "./ICrossChainVault.sol";
import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {ISliceToken} from "../interfaces/ISliceToken.sol";
import {IChainInfo} from "../interfaces/IChainInfo.sol";

import {Position, LzMsgGroupInfo} from "../Structs.sol";
import {TokenAmountUtils} from "../libs/TokenAmountUtils.sol";

contract CrossChainVault is ICrossChainVault, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISliceCore immutable sliceCore;
    IChainInfo immutable chainInfo;

    uint256 constant MIN_TIME_INTERVAL = 3600;

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
     * @dev Stores all commitments for a given commitment strategy
     */
    mapping(bytes32 strategyId => bytes32[] commitments) public commitmentsForStrategy;
    /**
     * @dev keccak256(abi.encodePacked(strategyId, userAddress)) to record if user is approved for a strategy
     */
    mapping(bytes32 strategyIdAddressHash => bool approved) public approvedForPrivateStrategy;
    /**
     * @dev Stores all oracle price updates for a given underlying asset token
     */
    mapping(address token => OraclePriceUpdate priceUpdate) public oraclePriceUpdates;
    /**
     * @dev keccak256(abi.encodePacked(strategyId, userAddress)) to record a user's slice token share from a given strategy
     */
    mapping(bytes32 strategyIdAddressHash => SliceTokenShare) public sliceTokenShares;

    mapping(bytes32 strategyId => mapping(address => uint256) commitedAmounts) public committedAmountsPerStrategy;
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

    constructor(ISliceCore _sliceCore, IChainInfo _chainInfo) Ownable(msg.sender) {
        sliceCore = _sliceCore;
        chainInfo = _chainInfo;
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

    function executeCommitmentStrategy(bytes32 strategyId) external nonReentrant vaultNotPaused {
        // TODO
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
                _updateCommitment(strategyId, amountToTransfer, _positions[i]);
            } else {
                // create cross-chain vault signal to send to vault on other chain
                CrossChainVaultSignal memory ccs = CrossChainVaultSignal({
                    strategyId: strategyId,
                    srcChainId: uint32(block.chainid),
                    ccvsType: CrossChainVaultSignalType.COMMIT,
                    user: msg.sender,
                    underlying: _positions[i].token,
                    committed: amountToTransfer
                });
                //      - if it is non-local use the same group LZ message logic as for the SliceCore
                (ccMsgs, lzMsgInfo) = groupAndSendLzMsg(ccMsgs, ccs, _positions[i], lzMsgInfo, fees);
            }
        }

        //      - send cross chain messages as needed
        if (lzMsgInfo.currentCount != 0) {
            _sendGroupedLzMsgs(ccMsgs, ccMsgs[0], lzMsgInfo, fees, msg.sender);
        }
    }

    function removeCommitmentFromStrategy(bytes32 commitmentId, uint256 amount) external nonReentrant {
        // TODO
    }

    function pullMintedTokenShares(bytes32 strategyId) external nonReentrant {
        // TODO
    }

    function updateUnderlyingAssetPrices(bytes32 strategyId) external nonReentrant vaultNotPaused {
        // TODO
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

    function groupAndSendLzMsg(
        CrossChainVaultSignal[] memory ccMsgs,
        CrossChainVaultSignal memory ccs,
        Position memory position,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees
    ) internal returns (CrossChainVaultSignal[] memory, LzMsgGroupInfo memory) {
        // TODO
    }

    function _sendGroupedLzMsgs(
        CrossChainVaultSignal[] memory ccMsgs,
        CrossChainVaultSignal memory ccs,
        LzMsgGroupInfo memory lzMsgInfo,
        uint128[] memory fees,
        address refundAddress
    ) private returns (CrossChainVaultSignal[] memory, LzMsgGroupInfo memory) {
        // TODO
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

    function _updateCommitment(bytes32 strategyId, uint256 amountToTransfer, Position memory position) private {
        uint256 nonce = nonces[msg.sender]++;
        bytes32 commitmentId = keccak256(
            abi.encodePacked(
                this.commitToStrategy.selector,
                block.chainid,
                msg.sender,
                address(this),
                strategyId,
                position.token,
                block.timestamp,
                nonce
            )
        );

        // update commitments
        Commitment memory _commitment = Commitment({
            id: commitmentId,
            strategyId: strategyId,
            chainId: block.chainid,
            asset: position.token,
            committed: amountToTransfer,
            consumed: 0
        });
        commitments[commitmentId] = _commitment;

        // update commitmentsForStrategy
        commitmentsForStrategy[strategyId].push(commitmentId);

        // update committedAmountsPerStrategy
        committedAmountsPerStrategy[strategyId][position.token] += amountToTransfer;
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
}
