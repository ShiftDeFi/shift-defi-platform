// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {
    // -- Access Control Errors --

    error Unauthorized();

    // -- State Errors --

    error AlreadyBlacklisted();
    error AlreadyWhitelisted();
    error NotImplemented();
    error TokenAlreadySet(address value);
    error AlreadySet();

    // -- Input Validation Errors --

    error ArrayLengthMismatch();
    error InvalidArrayLength();
    error IncorrectAmount();
    error IncorrectContainerStatus();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroArrayLength();
    error IncorrectContainerType(address container, uint8 expected, uint8 received);
    error DuplicatingAddressInArray(address entry);
    error IncorrectChainId(uint256 chainId);
    error SettingSameBooleanValue();

    // -- Business Logic Errors --

    error NotEnoughTokens(address token, uint256 amount, uint256 balance);
    error SwapFailed(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut);
}
