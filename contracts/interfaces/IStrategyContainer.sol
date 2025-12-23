// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IContainer} from "./IContainer.sol";

interface IStrategyContainer is IContainer {
    // ---- Enums ----

    enum CurrentBatchType {
        NoBatch,
        DepositBatch,
        WithdrawBatch
    }

    // ---- Structs ----

    struct NAVReport {
        uint256 nav0;
        uint256 nav1;
    }

    struct EnterStrategyLocalVars {
        uint256 tokenNumber;
        uint256 strategyIndex;
        uint256 enterBitmask;
        uint256 strategyMask;
        uint256 nav0;
        uint256 nav1;
        bool hasRemainder;
    }

    // ---- Events ----

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategyEntered(address indexed strategy, uint256 nav0, uint256 nav1, bool hasRemainder);
    event StrategyExited(address indexed strategy, uint256 share);
    event StrategyInputTokensUpdated(address indexed strategy);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event FeePctUpdated(uint256 oldFeePct, uint256 newFeePct);
    event BridgeCollectorUpdated(address oldBridgeCollector, address newBridgeCollector);
    event PriceOracleUpdated(address oldPriceOracle, address newPriceOracle);
    event ReshufflingModeUpdated(bool reshufflingMode);
    event EmergencyResolutionStarted(address strategy);
    event EmergencyResolutionCompleted();
    event StrategyNavResolved(address indexed strategy, uint256 resolvedNav);
    event StrategyOutputTokensUpdated(address indexed strategy);

    // ---- Errors ----

    error StrategyNotFound();
    error StrategyAlreadyHarvested(address strategy);
    error StrategyAlreadyExists();
    error StrategyAlreadyEntered(address strategy);
    error StrategyAlreadyExited(address strategy);
    error StrategyHarvestOutdated(address strategy);
    error IncorrectNav0();
    error NoSharesRegisteredForExit();
    error ActionUnavailableNotInReshufflingMode();
    error ActionUnavailableInReshufflingMode();
    error IncorrectEnterNav(uint256 nav0, uint256 nav1);
    error StrategyNavUnresolved(address strategy);
    error StrategyNavAlreadyResolved(address strategy);
    error EmergencyResolutionInProgress();
    error NotResolvingEmergency();
    error EmergencyResolutionNotCompleted(uint256 strategyUnresolvedNavBitmask);
    error MaxStrategiesReached();

    // ---- Functions ----

    /**
     * @notice Returns the treasury address.
     * @return The address of the treasury contract
     */
    function treasury() external view returns (address);

    /**
     * @notice Returns the price oracle address.
     * @return The address of the price oracle contract
     */
    function priceOracle() external view returns (address);

    /**
     * @notice Returns the fee percentage.
     * @return The fee percentage in basis points
     */
    function feePct() external view returns (uint256);

    /**
     * @notice Sets the bridge collector address.
     * @dev Can only be called by accounts with appropriate role.
     * @param newBridgeCollector The address of the new bridge collector
     */
    function setBridgeCollector(address newBridgeCollector) external;

    /**
     * @notice Sets the treasury address.
     * @dev Can only be called by accounts with appropriate role.
     * @param newTreasury The address of the new treasury contract
     */
    function setTreasury(address newTreasury) external;

    /**
     * @notice Sets the price oracle address.
     * @dev Can only be called by accounts with appropriate role.
     * @param newPriceOracle The address of the new price oracle contract
     */
    function setPriceOracle(address newPriceOracle) external;

    /**
     * @notice Sets the fee percentage.
     * @dev Can only be called by accounts with appropriate role.
     * @param newFeePct The new fee percentage in basis points
     */
    function setFeePct(uint256 newFeePct) external;

    /**
     * @notice Enables reshuffling mode.
     * @dev Can only be called by accounts with appropriate role.
     */
    function enableReshufflingMode() external;

    /**
     * @notice Disables reshuffling mode.
     * @dev Can only be called by accounts with appropriate role.
     */
    function disableReshufflingMode() external;

    /**
     * @notice Returns all registered strategies.
     * @return Array of strategy addresses
     */
    function getStrategies() external view returns (address[] memory);

    /**
     * @notice Checks if an address is a registered strategy.
     * @param strategy The address to check
     * @return True if the address is a registered strategy, false otherwise
     */
    function isStrategy(address strategy) external view returns (bool);

    /**
     * @notice Adds a new strategy to the container.
     * @dev Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy contract to add
     * @param inputTokens Array of input token addresses for the strategy
     * @param outputTokens Array of output token addresses for the strategy
     */
    function addStrategy(address strategy, address[] calldata inputTokens, address[] calldata outputTokens) external;

    /**
     * @notice Removes a strategy from the container.
     * @dev Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy contract to remove
     */
    function removeStrategy(address strategy) external;

    /**
     * @notice Sets the input tokens for a strategy.
     * @dev Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy
     * @param inputTokens Array of input token addresses
     */
    function setStrategyInputTokens(address strategy, address[] calldata inputTokens) external;

    /**
     * @notice Sets the output tokens for a strategy.
     * @dev Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy
     * @param outputTokens Array of output token addresses
     */
    function setStrategyOutputTokens(address strategy, address[] calldata outputTokens) external;

    /**
     * @notice Returns the total NAV values (nav0 and nav1).
     * @return nav0 The NAV value before the current batch
     * @return nav1 The NAV value after the current batch
     */
    function getTotalNavs() external view returns (uint256, uint256);

    /**
     * @notice Enters a strategy in reshuffling mode.
     * @dev Can only be called when in reshuffling mode. Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy to enter
     * @param inputAmounts Array of input token amounts
     * @param minNavDelta The minimum NAV delta required
     */
    function enterInReshufflingMode(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external;

    /**
     * @notice Exits a strategy in reshuffling mode.
     * @dev Can only be called when in reshuffling mode. Can only be called by accounts with appropriate role.
     * @param strategy The address of the strategy to exit
     * @param share The share amount to exit
     * @param maxNavDelta The maximum NAV delta allowed
     */
    function exitInReshufflingMode(address strategy, uint256 share, uint256 maxNavDelta) external;

    /**
     * @notice Starts emergency resolution process.
     * @dev Can only be called by accounts with appropriate role.
     */
    function startEmergencyResolution() external;

    /**
     * @notice Checks if emergency resolution is in progress.
     * @return True if emergency resolution is in progress, false otherwise
     */
    function isResolvingEmergency() external view returns (bool);

    /**
     * @notice Completes emergency resolution process.
     * @dev Can only be called when all strategy NAVs have been resolved.
     */
    function completeEmergencyResolution() external;

    /**
     * @notice Resolves the NAV for a strategy during emergency resolution.
     * @dev Can only be called during emergency resolution. Can only be called by accounts with appropriate role.
     * @param resolvedNav The resolved NAV value for the strategy
     */
    function resolveStrategyNav(uint256 resolvedNav) external;

    /**
     * @notice Checks if a strategy's NAV is unresolved.
     * @param strategy The address of the strategy to check
     * @return True if the strategy's NAV is unresolved, false otherwise
     */
    function isStrategyNavUnresolved(address strategy) external view returns (bool);
}
