// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "./ISwapRouter.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ICrossChainContainer} from "./ICrossChainContainer.sol";

interface IContainerPrincipal {
    // ---- Enums ----

    enum ContainerPrincipalStatus {
        Idle, // no active deposit and withdrawal requests
        DepositRequestRegistered, // deposit request registered, allowed only swaps and allocation.
        DepositRequestSent, // withdrawal request registered, allowed only withdrawal request broadcast
        DepositResponseReceived, // nothing allowed
        WithdrawalRequestRegistered, // nothing allowed
        WithdrawalRequestSent, // nothing allowed
        WithdrawalResponseReceived, // nothing allowed
        BridgeClaimed // nothing allowed
    }

    // ---- Structs ----

    struct SendDepositRequestLocalVars {
        address[] tokens;
        uint256[] minAmounts;
    }

    struct ReportDepositLocalVars {
        uint256 nav0;
        uint256 nav1;
        uint256 remainder;
    }

    // ---- Events ----

    event DepositRequestRegistered(uint256 amount);
    event WithdrawalRequestRegistered(uint256 shares);
    event DepositRequestSent();
    event WithdrawalRequestSent(uint256 shares);
    event DepositResponseReceived(uint256 claimCointer, uint256 nav0, uint256 nav1);
    event WithdrawalResponseReceived(uint256 claimCounter);
    event DepositReported(uint256 nav0, uint256 nav1, uint256 remainder);
    event WithdrawalReported();

    // ---- Functions ----

    function registerDepositRequest(uint256 amount) external;

    function registerWithdrawRequest(uint256 amount) external;

    function sendDepositRequest(
        ICrossChainContainer.MessageInstruction memory messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    function reportDeposit() external payable;

    function claim(address bridgeAdapter, address token) external;
}
