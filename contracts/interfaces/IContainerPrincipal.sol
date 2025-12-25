// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "./ISwapRouter.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ICrossChainContainer} from "./ICrossChainContainer.sol";

interface IContainerPrincipal is ICrossChainContainer {
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

    /**
     * @notice Returns the current status of the container.
     * @return The current ContainerPrincipalStatus
     */
    function status() external view returns (ContainerPrincipalStatus);

    /**
     * @notice Returns the NAV value after harvesting and before deposit.
     * @return The NAV value before the deposit batch
     */
    function nav0() external view returns (uint256);

    /**
     * @notice Returns the NAV value after deposit.
     * @return The NAV value after the deposit batch
     */
    function nav1() external view returns (uint256);

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
     * @notice Sends a deposit request to the peer container on the remote chain.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be DepositRequestRegistered. Bridges tokens and sends a message.
     * @param messageInstruction The message instruction for the cross-chain message
     * @param bridgeAdapters Array of bridge adapter addresses to use
     * @param bridgeInstructions Array of bridge instructions for each adapter
     */
    function sendDepositRequest(
        ICrossChainContainer.MessageInstruction memory messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable;

    /**
     * @notice Sends a withdrawal request to the peer container on the remote chain.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be WithdrawalRequestRegistered.
     * @param messageInstruction The message instruction for the cross-chain message
     */
    function sendWithdrawRequest(ICrossChainContainer.MessageInstruction memory messageInstruction) external payable;

    /**
     * @notice Reports deposit results to the vault.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be DepositResponseReceived.
     */
    function reportDeposit() external payable;

    /**
     * @notice Reports withdrawal results to the vault.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires status to be WithdrawalResponseReceived.
     */
    function reportWithdrawal() external payable;

    /**
     * @notice Claims tokens from a bridge adapter.
     * @dev Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapter The address of the bridge adapter
     * @param token The address of the token to claim
     */
    function claim(address bridgeAdapter, address token) external;

    /**
     * @notice Claims tokens from multiple bridge adapters.
     * @dev Can only be called by accounts with OPERATOR_ROLE.
     * @param bridgeAdapters Array of bridge adapter addresses
     * @param tokens Array of token addresses to claim
     */
    function claimMultiple(address[] calldata bridgeAdapters, address[] calldata tokens) external;
}
