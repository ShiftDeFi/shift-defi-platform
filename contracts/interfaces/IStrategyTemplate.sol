// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStrategyTemplate {
    // ---- Structs ----

    struct EnterLocalVars {
        bytes32 currentStateId;
        bytes32 enterStateId;
        uint256 enterStateBitmask;
        uint256 stateToNavBeforeEnter;
        uint256 stateToNavAfterEnter;
        uint256[] remainingAmounts;
        bool hasRemainder;
    }

    struct EnterToStateLocalVars {
        uint256 toStateBitmask;
        bytes32 currentStateId;
        uint256 currentStateBitmask;
        uint256 stateToNavBeforeEnter;
        uint256 stateToNavAfterEnter;
    }

    struct EnterInEmergencyModeLocalVars {
        bytes32 currentStateId;
        bytes32 targetStateId;
        uint256 currentStateBitmask;
        uint256 navBeforeEnter;
        uint256 navAfterEnter;
    }

    struct ExitLocalVars {
        bytes32 currentStateId;
        uint256 currentStateBitmask;
        uint256 currentStateNavBeforeExit;
        uint256 currentStateNavAfterExit;
        uint256 exitLiquidity;
        uint256 tokenShare;
        address[] outputTokens;
        uint256[] outputAmounts;
        uint256[] amountsBeforeExit;
        bool hasRemainder;
    }

    struct HarvestLocalVars {
        bytes32 currentStateId;
        uint256 currentStateBitmask;
        uint256 currentStateNav;
        address swapRouter;
        address treasury;
        uint256 feePct;
    }

    struct PrepareFundsAfterExitLocalVars {
        address[] outputTokens;
        uint256[] outputAmounts;
        uint256 length;
        address container;
        bool hasRemainder;
    }

    struct PrepareFundsAfterEnterLocalVars {
        uint256 length;
        address container;
        address[] tokens;
        uint256[] amounts;
        bool hasRemainder;
    }

    struct EmergencyExitLocalVars {
        bytes32 currentStateId;
        uint256 currentStateBitmask;
        uint256 toStateBitmask;
        bool isResolvingEmergency;
        bool isExitSuccess;
    }

    // ---- Events ----

    event Entered(uint256 navBefore, uint256 navAfter, bool hasRemainder);
    event Exited(uint256 navBefore, uint256 navAfter, bytes32 stateId);
    event EmergencyExited(bytes32 toStateId);
    event Harvested(bytes32 stateId, uint256 navAfter);
    event EmergencyExitFailed(bytes32 toStateId);
    event EmergencyExitSucceeded(bytes32 toStateId);
    event ReenteredToState(bytes32 stateId);
    event StateUpdated(bytes32 oldStateId, bytes32 newStateId, uint256 newStateBitmask);
    event NavResolutionModeUpdated(bool isNavResolutionMode);
    event EmergencyModeUpdated(bool isEmergencyMode);
    event InputTokenSet(address);
    event OutputTokenSet(address);

    // ---- Errors ----

    error EnterUnavailable();
    error ExitUnavailable();
    error EmergencyExitUnavailable();
    error SlippageCheckFailed(uint256 navBefore, uint256 navAfter, uint256 minNavDelta);
    error NavResolutionModeActivated();
    error NavResolutionModeNotActivated();
    error EmergencyModeActivated();
    error StateNotFound(bytes32 stateId);
    error NotInTargetState(bytes32 currentStateId, uint256 currentStateBitmask);
    error StateAlreadyExists(bytes32 stateId);
    error TargetStateAlreadySet();

    // ---- Functions ----

    /**
     * @notice Returns the identifier of the current allocation state.
     */
    function currentStateId() external view returns (bytes32);

    /**
     * @notice Returns the net asset value (NAV) of the current state in notion units.
     */
    function currentStateNav() external view returns (uint256);

    /**
     * @notice Returns whether NAV resolution mode is active.
     * @dev Used during emergency flows to lock normal enter/exit operations.
     * @return True if NAV resolution mode is active, false otherwise.
     */
    function isNavResolutionMode() external view returns (bool);

    /**
     * @notice Enters the strategy using the provided input token amounts.
     * @dev Callable only by the strategy container. Input array order must match `getInputTokens()`.
     *      Reverts unless NAV increases by at least `minNavDelta`.
     * @param inputAmounts Amounts of input tokens provided by the container.
     * @param minNavDelta Minimum required NAV increase (notion units) after enter.
     * @return stateNavAfter NAV after enter (notion units).
     * @return hasRemainder True if any funds remain to be prepared for the agent.
     * @return remainingAmounts Amounts remaining for the agent per input token.
     */
    function enter(
        uint256[] memory inputAmounts,
        uint256 minNavDelta
    ) external payable returns (uint256, bool, uint256[] memory);

    /**
     * @notice Exits the strategy proportionally to a share of the position.
     * @dev Callable only by the strategy container. `share` is in basis points (10000 = 100%).
     *      Reverts if NAV drops by more than `maxNavDelta`.
     * @param share Portion of the position to exit in basis points.
     * @param maxNavDelta Maximum allowed NAV decrease (notion units) during exit.
     * @return outputTokens Tokens transferred back to the container.
     * @return outputAmounts Amounts returned per token.
     */
    function exit(uint256 share, uint256 maxNavDelta) external payable returns (address[] memory, uint256[] memory);

    /**
     * @notice Harvests rewards, applies fees and reinvests it into the strategy.
     * @dev Callable by the strategy container or HARVEST_MANAGER_ROLE.
     * @return navAfter NAV after harvest (notion units).
     */
    function harvest() external payable returns (uint256);

    /**
     * @notice Performs an emergency exit to a specific state.
     * @dev Callable by the strategy container or EMERGENCY_MANAGER_ROLE.
     * @param toStateId Destination state identifier for the emergency exit.
     * @param share Portion of the position to exit in basis points (10000 = 100%).
     */
    function emergencyExit(bytes32 toStateId, uint256 share) external payable;

    /**
     * @notice Performs multiple emergency exits in a single call.
     * @dev Callable by the strategy container or EMERGENCY_MANAGER_ROLE.
     * @param toStateIds Array of destination state identifiers for emergency exits.
     * @param shares Portions to exit per state in basis points.
     */
    function emergencyExitMultiple(bytes32[] calldata toStateIds, uint256[] calldata shares) external payable;

    /**
     * @notice Internal function to attempt an emergency exit safely.
     * @dev Can only be called by the contract itself. Used by `emergencyExit` to execute exit operations in a try-catch pattern.
     * @param toStateId Destination state identifier for the emergency exit.
     * @param share Portion of the position to exit in basis points (10000 = 100%).
     */
    function tryEmergencyExit(bytes32 toStateId, uint256 share) external;

    /**
     * @notice Sets the list of allowed input tokens.
     * @dev Callable only by the strategy container. Tokens cannot be zero addresses or duplicates.
     * @param inputTokens Token addresses allowed for entering the strategy.
     */
    function setInputTokens(address[] memory inputTokens) external;

    /**
     * @notice Sets the list of allowed output tokens.
     * @dev Callable only by the strategy container. Tokens cannot be zero addresses or duplicates.
     * @param outputTokens Token addresses expected when exiting the strategy.
     */
    function setOutputTokens(address[] memory outputTokens) external;

    /**
     * @notice Returns the net asset value for a specific state.
     * @param stateId State identifier.
     */
    function stateNav(bytes32 stateId) external view returns (uint256);

    /**
     * @notice Returns the currently configured input tokens.
     */
    function getInputTokens() external view returns (address[] memory);

    /**
     * @notice Returns the currently configured output tokens.
     */
    function getOutputTokens() external view returns (address[] memory);

    /**
     * @notice Converts a token amount into notion denomination using the oracle aggregator.
     * @dev Uses the price oracle from the strategy container to get relative value.
     * @param token Token address to convert.
     * @param amount Token amount to convert.
     * @return Notion-denominated value of the token amount.
     */
    function getTokenAmountInNotion(address token, uint256 amount) external view returns (uint256);
}
