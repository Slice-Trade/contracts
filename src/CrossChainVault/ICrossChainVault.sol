// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./CrossChainVaultStructs.sol";

interface ICrossChainVault {
    event CommitmentStrategyCreated(bytes32 indexed strategyId);
    event CommitmentStrategyTargetModified(bytes32 indexed strategyId, uint256 indexed newTarget);
    event CommitmentStrategyExecuted(bytes32 indexed strategyId);
    event CommittedToStrategy(bytes32 indexed strategyId, bytes32 indexed commitmentId);
    event RemovedCommitmentFromStrategy(bytes32 indexed commitmentId, uint256 indexed amount);
    event PulledMintedTokenShares(bytes32 indexed strategyId, address indexed user, uint256 indexed sliceTokenAmount);
    event UpdatedUnderlyingAssetPrices(bytes32 indexed strategyId);
    event ChangedUserApprovalToCommitmentStrategy(bytes32 indexed strategyId, address indexed user, bool indexed isApproved);
    event VaultPaused();
    event VaultRestarted();

    error VaultIsPaused();
    error VaultNotPaused();

    error UnregisteredSliceToken();
    error InvalidTimestamp();
    error InvalidTimeInterval();
    error InvalidAmount();

    error InvalidStrategyId();
    error Unauthorized();
    error InvalidStrategyState();
    error StrategyNotPrivate();

    error StrategyOver();


    /**
     * @dev This function allows users to create commitment strategies.
     * They must be able to specify either the mint amount target or the timestamp when the minting can occur.
     * If they specify a mint amount, mint can be started anytime that amount threshold is reached.
     * If they specify a timestamp, the mint can be started anytime after the timestamp has been reached with whatever amount is in the vault.
     * This could even be repeated.
     *
     * @param token The slice token address this commitment strategy is aimed at
     * @param target The mint amount target or mint timestamp (depending on the strategy type)
     * @param strategyType The type of the strategy, can be either mint amount target or timestamp target
     * @param isPrivate Whether the strategy is private. If private only approved addresses can commit
     */
    function createCommitmentStrategy(
        address token,
        uint256 target,
        CommitmentStrategyType strategyType,
        bool isPrivate
    ) external;

    /**
     * @dev This allows the strategy creator to increase/decrease the target mint amount or change the timestamp for a strategy.
     *
     * @param strategyId The ID of the strategy whose target the creator is modifying
     * @param newTarget The new target mint amount or timestamp
     */
    function modifyCommitmentStrategyTarget(bytes32 strategyId, uint256 newTarget) external;

    /**
     * @dev Once the condition for a strategy has been reached (either the amount or the timestamp),
     * and also the oracle price has been updated for the underyling assets in the strategy
     * anyone can execute the strategy - this will mint the slice tokens to the vault
     *
     * @param strategyId The id of the commitment strategy to execute
     */
    function executeCommitmentStrategy(bytes32 strategyId) external;

    /**
     * @dev This is for users to deposit underlying assets to a commitment strategy
     *
     * @param strategyId The ID of the strategy to commit to
     * @param assets The underyling assets to commit
     * @param amounts The amounts of the underlying assets to commit
     */
    function commitToStrategy(bytes32 strategyId, address[] memory assets, uint256[] memory amounts) external;

    /**
     * @dev This is for the users to remove underlying assets they already committed to the strategy
     *
     * @param commitmentId The ID of the commitment for which the user is removing funds from
     * @param amount The amount of funds to remove
     */
    function removeCommitmentFromStrategy(bytes32 commitmentId, uint256 amount) external;

    /**
     * @dev Once a commitment strategy has been executed, the slice tokens will be in the vault.
     * Users who provided assets to that strategy can call this function to pull their respective slice tokens.
     *
     * @param strategyId The ID of the strategy to pull the shares for
     */
    function pullMintedTokenShares(bytes32 strategyId) external;

    /**
     * @dev This function updates the USD price for underyling assets using an off-chain oracle.
     *
     * @param strategyId The ID of the startegy to update the underlying asset prices for
     */
    function updateUnderlyingAssetPrices(bytes32 strategyId) external;

    /**
     * @dev For private commitment strategies, the creator can whitelist addresses to commit.
     *
     * @param strategyId The ID of the strategy
     * @param user The address of the user
     * @param isApproved Whether the user is approved to comoit or not
     */
    function changeUserApprovalToCommitmentStrategy(bytes32 strategyId, address user, bool isApproved) external;

    /**
     * @dev In case any problem is discovered, the owner of the vault can pause all functionalities except for withdrawals.
     */
    function pauseVault() external;

    /**
     * @dev Allows the vault owner to restart the vault after a pause
     */
    function restartVault() external;
}
