// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStrategyContainer} from "./IStrategyContainer.sol";

interface IContainerLocal is IStrategyContainer {
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

    /**
     * @notice Returns the current status of the container.
     * @return The current ContainerLocalStatus
     */
    function status() external view returns (ContainerLocalStatus);

    /**
     * @notice Returns the registered withdrawal share amount.
     * @return The share amount registered for withdrawal
     */
    function registeredWithdrawShareAmount() external view returns (uint256);

    /**
     * @notice Registers a deposit request from the vault.
     * @dev Can only be called by the vault. Requires container status to be Idle.
     * @param amount The amount of notion tokens to deposit
     */
    function registerDepositRequest(uint256 amount) external;

    /**
     * @notice Registers a withdrawal request from the vault.
     * @dev Can only be called by the vault. Requires container status to be Idle.
     * @param amount The share amount to withdraw
     */
    function registerWithdrawRequest(uint256 amount) external;

    /**
     * @notice Reports deposit results to the vault.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be AllStrategiesEntered.
     */
    function reportDeposit() external;

    /**
     * @notice Reports withdrawal results to the vault.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be AllStrategiesExited.
     */
    function reportWithdraw() external;

    /**
     * @notice Enters a single strategy.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires appropriate container status.
     * @param strategy The address of the strategy to enter
     * @param inputAmounts Array of input token amounts
     * @param minNavDelta The minimum NAV delta required
     */
    function enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external;

    /**
     * @notice Enters multiple strategies.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires appropriate container status.
     * @param strategies Array of strategy addresses to enter
     * @param inputAmounts Array of arrays, where each inner array contains input token amounts for the corresponding strategy
     * @param minNavDelta Array of minimum NAV deltas for each strategy
     */
    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external;

    /**
     * @notice Exits a single strategy.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires appropriate container status.
     * @param strategy The address of the strategy to exit
     * @param maxNavDelta The maximum NAV delta allowed
     */
    function exitStrategy(address strategy, uint256 maxNavDelta) external;

    /**
     * @notice Exits multiple strategies.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires appropriate container status.
     * @param strategies Array of strategy addresses to exit
     * @param maxNavDeltas Array of maximum NAV deltas for each strategy
     */
    function exitStrategyMultiple(address[] calldata strategies, uint256[] calldata maxNavDeltas) external;

    /**
     * @notice Withdraws tokens to the reshuffling gateway.
     * @dev Can only be called when in reshuffling mode. Can only be called by accounts with OPERATOR_ROLE.
     * @param tokens Array of token addresses to withdraw
     * @param amounts Array of token amounts to withdraw
     */
    function withdrawToReshufflingGateway(address[] memory tokens, uint256[] memory amounts) external;
}
