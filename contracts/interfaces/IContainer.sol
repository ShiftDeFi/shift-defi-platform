// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IContainer {
    // ---- Enums ----

    enum ContainerType {
        Local,
        Principal,
        Agent
    }

    // ---- Events ----

    event SwapRouterUpdated(address indexed previousSwapRouter, address indexed newSwapRouter);
    event WhitelistedTokenDustThresholdUpdated(address indexed token, uint256 threshold);

    // ---- Errors ----

    error AlreadyWhitelistedToken();
    error NotWhitelistedToken(address token);
    event TokenWhitelistUpdated(address indexed token, bool isWhitelisted);
    error WhitelistedTokensOnBalance();

    // ---- Functions ----

    function containerType() external view returns (ContainerType);

    function isTokenWhitelisted(address token) external view returns (bool);

    function swapRouter() external view returns (address);

    function notion() external view returns (address);
}
