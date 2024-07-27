// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./CrossChainVaultStructs.sol";
import {ICrossChainVault} from "./ICrossChainVault.sol";
import {ISliceCore} from "../interfaces/ISliceCore.sol";
import {IChainInfo} from "../interfaces/IChainInfo.sol";

contract CrossChainVault is ICrossChainVault, Ownable2Step, ReentrancyGuard {
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
        if (strategyId == bytes32(0) || strategyId != _strategy.id) {
            revert InvalidStrategyId();
        }

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

    function commitToStrategy(bytes32 strategyId, address asset, uint256 amount) external nonReentrant vaultNotPaused {
        // TODO
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
        if (strategyId == bytes32(0) || strategyId != _strategy.id) {
            revert InvalidStrategyId();
        }

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
        isPaused = false;
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
}
