// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "./ISwapRouter.sol";

interface IContainer {
    // ---- Enums ----

    enum ContainerType {
        Local,
        Principal,
        Agent
    }

    // ---- Structs ----

    struct ContainerInitParams {
        address vault;
        address notion;
        address defaultAdmin;
        address operator;
        address swapRouter;
    }

    // ---- Events ----

    event SwapRouterUpdated(address indexed previousSwapRouter, address indexed newSwapRouter);
    event TokenWhitelistUpdated(address indexed token, bool isWhitelisted);
    event WhitelistedTokenDustThresholdUpdated(address indexed token, uint256 threshold);

    // ---- Errors ----

    error AlreadyWhitelistedToken();
    error NotWhitelistedToken(address token);
    error WhitelistedTokensOnBalance();

    // ---- Functions ----

    function vault() external view returns (address);

    function notion() external view returns (address);

    function swapRouter() external view returns (address);

    function containerType() external view returns (ContainerType);

    function isTokenWhitelisted(address token) external view returns (bool);

    function whitelistToken(address token) external;

    function blacklistToken(address token) external;

    function setWhitelistedTokenDustThreshold(address token, uint256 threshold) external;

    function setSwapRouter(address newSwapRouter) external;

    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata instructions) external;
}
