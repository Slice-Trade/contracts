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
     * keccak256(abi.encodePacked(strategyId, userAddress)) to record a user's slice token share from a given strategy
     */
    mapping(bytes32 strategyIdAddressHash => SliceTokenShare) public sliceTokenShares;

    constructor() Ownable(msg.sender) {}

    function createCommitmentStrategy(
        address token,
        uint256 target,
        CommitmentStrategyType strategyType,
        bool isPrivate
    ) external {
        // TODO
    }

    function modifyCommitmentStrategyTarget(bytes32 strategyId, uint256 newTarget) external {
        // TODO
    }

    function executeCommitmentStrategy(bytes32 strategyId) external {
        // TODO
    }

    function commitToStrategy(bytes32 strategyId, address asset, uint256 amount) external {
        // TODO
    }

    function removeCommitmentFromStrategy(bytes32 commitmentId, uint256 amount) external {
        // TODO
    }

    function pullMintedTokenShares(bytes32 strategyId) external {
        // TODO
    }

    function updateUnderlyingAssetPrices(bytes32 strategyId) external {
        // TODO
    }

    function changeUserApprovalToCommitmentStrategy(bytes32 strategyId, address user, bool isApproved) external {
        // TODO
    }

    function pauseVault() external onlyOwner {
        // TODO
    }

    function restartVault() external onlyOwner {
        // TODO
    }
}
