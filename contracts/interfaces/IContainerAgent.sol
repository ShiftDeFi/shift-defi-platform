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

    function status() external view returns (ContainerAgentStatus);

    function registeredWithdrawShareAmount() external view returns (uint256);

    function enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external;

    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external;

    function exitStrategy(address strategy, uint256 minNavDelta) external;

    function exitStrategyMultiple(address[] calldata strategies, uint256[] calldata minNavDeltas) external;

    function reportDeposit(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    function reportWithdrawal(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    function claim(address bridgeAdapter, address token) external;

    function claimInReshufflingMode(address bridgeAdapter, address token) external;

    function claimMultiple(address[] calldata bridgeAdapters, address[] calldata tokens) external;

    function withdrawToReshufflingGateway(
        address[] memory bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata instructions
    ) external;
}
