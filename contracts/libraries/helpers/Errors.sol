// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {
    // -- Access Control Errors --

    error Unauthorized();
    error OnlyAgent();

    // -- State Errors --

    error AlreadyBlacklisted();
    error AlreadyInitialized();
    error AlreadyWhitelisted();
    error EmergencyModeEnabled();
    error NotImplemented();
    error NotInRepairingMode();
    error TokenAlreadySet(address value);
    error AlreadySet();

    // -- Input Validation Errors --

    error ArrayLengthMismatch();
    error IncorrectAmount();
    error IncorrectContainerStatus();
    error IncorrectInput();
    error InvalidDataLength();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroArrayLength();
    error NonZeroAmount();
    error NotFound();
    error IncorrectContainerType(address container, uint8 expected, uint8 received);

    // -- Business Logic Errors --

    error NotEnoughTokens(address token, uint256 amount);
    error SwapFailed(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut);
}
