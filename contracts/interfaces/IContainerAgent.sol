// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IContainerAgent {
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

    // ---- Functions ----
    function claim(address bridgeAdapter, address token) external;

    function claimMultiple(address[] memory bridgeAdapters, address[] memory tokens) external;
}
