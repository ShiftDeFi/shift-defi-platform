// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IContainerLocal {
    // ---- Enums ----

    enum ContainerLocalStatus {
        Idle,
        DepositRequestRegistered,
        AllStrategiesEntered,
        WithdrawalRequestRegistered,
        AllStrategiesExited
    }

    // ---- Events ----

    event AllStrategiesEntered();
    event AllStrategiesExited();

    // ---- Functions ----

    function registerDepositRequest(uint256 amount) external;

    function registerWithdrawRequest(uint256 amount) external;

    function reportDeposit() external;

    function reportWithdraw() external;

    function enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external;

    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external;

    function exitStrategy(address strategy, uint256 minNavDelta) external;

    function exitStrategyMultiple(address[] calldata strategies, uint256[] calldata minNavDelta) external;
}
