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

    // -- Business Logic Errors --

    error NotEnoughTokens(address token, uint256 amount);
}
