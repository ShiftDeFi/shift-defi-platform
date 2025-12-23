// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICrossChainContainer} from "./ICrossChainContainer.sol";
import {IStrategyContainer} from "./IStrategyContainer.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";

interface IContainerAgent is ICrossChainContainer, IStrategyContainer {
    // ---- Enums ----

    enum ContainerAgentStatus {
        Idle,
        DepositRequestReceived,
        WithdrawalRequestReceived,
        BridgeClaimed,
        AllStrategiesEntered,
        AllStrategiesExited
    }

    struct ReportDepositLocalVars {
        address peerContainerCached;
        address[] tokens;
        uint256[] minAmounts;
        uint256 nav0;
        uint256 nav1;
    }

    // ---- Events ----

    event AllStrategiesEntered();
    event AllStrategiesExited();
    event DepositReported(uint256 nav0, uint256 nav1);
    event WithdrawalReported(uint256 shares);
    event DepositRequestReceived(uint256 claimCounter);
    event WithdrawalRequestReceived(uint256 shares);

    // ---- Errors ----

    // ---- Functions ----

    /**
     * @notice Returns the current status of the container.
     * @return The current ContainerAgentStatus
     */
    function status() external view returns (ContainerAgentStatus);

    /**
     * @notice Returns the registered withdrawal share amount.
     * @return The share amount registered for withdrawal
     */
    function registeredWithdrawShareAmount() external view returns (uint256);

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
     * @param minNavDelta The minimum NAV delta required
     */
    function exitStrategy(address strategy, uint256 minNavDelta) external;

    /**
     * @notice Exits multiple strategies.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires appropriate container status.
     * @param strategies Array of strategy addresses to exit
     * @param minNavDeltas Array of minimum NAV deltas for each strategy
     */
    function exitStrategyMultiple(address[] calldata strategies, uint256[] calldata minNavDeltas) external;

    /**
     * @notice Reports deposit results to the peer container.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be AllStrategiesEntered. Bridges tokens and sends a message.
     * @param messageInstruction The message instruction for the cross-chain message
     * @param bridgeAdapters Array of bridge adapter addresses to use
     * @param bridgeInstructions Array of bridge instructions for each adapter
     */
    function reportDeposit(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    /**
     * @notice Reports withdrawal results to the peer container.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be AllStrategiesExited. Bridges tokens and sends a message.
     * @param messageInstruction The message instruction for the cross-chain message
     * @param bridgeAdapters Array of bridge adapter addresses to use
     * @param bridgeInstructions Array of bridge instructions for each adapter
     */
    function reportWithdrawal(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    /**
     * @notice Claims tokens from a bridge adapter.
     * @dev Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapter The address of the bridge adapter
     * @param token The address of the token to claim
     */
    function claim(address bridgeAdapter, address token) external;

    /**
     * @notice Claims tokens from a bridge adapter in reshuffling mode.
     * @dev Can only be called when in reshuffling mode. Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapter The address of the bridge adapter
     * @param token The address of the token to claim
     */
    function claimInReshufflingMode(address bridgeAdapter, address token) external;

    /**
     * @notice Claims tokens from multiple bridge adapters.
     * @dev Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapters Array of bridge adapter addresses
     * @param tokens Array of token addresses to claim
     */
    function claimMultiple(address[] calldata bridgeAdapters, address[] calldata tokens) external;

    /**
     * @notice Withdraws tokens to the reshuffling gateway.
     * @dev Can only be called when in reshuffling mode. Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapters Array of bridge adapter addresses to use
     * @param instructions Array of bridge instructions for each adapter
     */
    function withdrawToReshufflingGateway(
        address[] memory bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata instructions
    ) external;
}
