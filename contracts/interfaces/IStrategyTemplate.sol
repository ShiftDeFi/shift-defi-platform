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

    function currentStateId() external view returns (bytes32);

    function currentStateNav() external view returns (uint256);

    function enter(
        uint256[] memory inputAmounts,
        uint256 minNavDelta
    ) external payable returns (uint256, bool, uint256[] memory);

    function exit(
        uint256 share,
        uint256 minLiquidityAfterExit
    ) external payable returns (address[] memory, uint256[] memory);

    function harvest() external payable returns (uint256);

    function emergencyExit(bytes32 toStateId, uint256 share) external payable;

    function emergencyExitMultiple(bytes32[] calldata toStateIds, uint256[] calldata shares) external payable;

    function setInputTokens(address[] memory inputTokens) external;

    function setOutputTokens(address[] memory outputTokens) external;

    function stateNav(bytes32 stateId) external view returns (uint256);

    function getInputTokens() external view returns (address[] memory);

    function getOutputTokens() external view returns (address[] memory);
}
