// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IContainer {
    enum ContainerType {
        Local,
        Principal,
        Agent
    }

    event SwapRouterUpdated(address indexed previousSwapRouter, address indexed newSwapRouter);
    event WhitelistedTokenDustThresholdUpdated(address indexed token, uint256 threshold);

    error AlreadyWhitelistedToken();
    error NotWhitelistedToken(address token);
    event TokenWhitelistUpdated(address indexed token, bool isWhitelisted);
    error WhitelistedTokensOnBalance();

    function containerType() external view returns (ContainerType);
    function isTokenWhitelisted(address token) external view returns (bool);
    function swapRouter() external view returns (address);
}
