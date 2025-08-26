// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStrategyTemplate {
    struct EnterLocalVars {
        uint256 allocatedNavBeforeEnter;
        uint256 allocatedNavAfterEnter;
        uint256[] remainingAmounts;
        bool hasRemainder;
    }

    struct ExitLocalVars {
        bytes32 currentStateId;
        uint256 allocatedNavBeforeExit;
        uint256 allocatedNavAfterExit;
        uint256[] amountsBeforeExit;
        address[] outputTokens;
        uint256[] remainingAmounts;
        bool isOnlyTokenState;
    }

    struct ReenterAfterEmergencyExitLocalVars {
        bytes32 currentStateId;
        uint256 allocatedNavBeforeEnter;
        uint256 allocatedNavAfterEnter;
        bool hasRemainder;
    }

    struct TakeFeesLocalVars {
        address treasury;
        uint256 feePct;
        uint256 lengthCached;
        address[] inputTokens;
    }

    event Entered(uint256 navBefore, uint256 navAfter, bool hasRemainder);
    event Exited(uint256 navBefore, uint256 navAfter, bytes32 stateId);
    event EmergencyExited(bytes32 toStateId);
    event Harvested(uint256 navAfter);

    error SlippageCheckFailed(uint256 allocatedNavBeforeExit, uint256 allocatedNavAfterExit);
    error EmergencyModeEnabled();
    error EmergencyModeDisabled();
    error WrongStateForExit(bytes32 stateId);
    error WrongStateForEmergencyExit(bytes32 stateId);

    function enter(
        uint256[] memory inputAmounts,
        uint256 minNavDelta
    ) external payable returns (uint256, bool, uint256[] memory);

    function reenterAfterEmergencyExit(uint256 minNavDelta) external payable;

    function exit(uint256 share, uint256 minNavDelta) external payable returns (address[] memory, uint256[] memory);

    function harvest() external payable returns (uint256);

    function emergencyExit(bytes32 toStateId) external payable;

    function nav() external view returns (uint256);

    function allocatedNav(bytes32 stateId) external view returns (uint256);

    function inputTokens() external view returns (address[] memory);

    function outputTokens() external view returns (address[] memory);
}
