// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStrategyContainer {
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
    error NotResolvingEmergency();
    error EmergencyResolutionNotCompleted(uint256 strategyUnresolvedNavBitmask);
    error MaxStrategiesReached();

    // ---- Functions ----

    function treasury() external view returns (address);

    function feePct() external view returns (uint256);

    function priceOracle() external view returns (address);

    function isResolvingEmergency() external view returns (bool);

    function startEmergencyResolution() external;

    function completeEmergencyResolution() external;

    function resolveStrategyNav(uint256 resolvedNav) external;

    function setStrategyInputTokens(address strategy, address[] calldata inputTokens) external;

    function setStrategyOutputTokens(address strategy, address[] calldata outputTokens) external;
}
