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

    /**
     * @notice Returns the vault address.
     * @return The address of the vault contract
     */
    function vault() external view returns (address);

    /**
     * @notice Returns the notion token address.
     * @return The address of the notion token contract
     */
    function notion() external view returns (address);

    /**
     * @notice Returns the swap router address.
     * @return The address of the swap router contract
     */
    function swapRouter() external view returns (address);

    /**
     * @notice Returns the container type.
     * @return The type of container (Local, Principal, or Agent)
     */
    function containerType() external view returns (ContainerType);

    /**
     * @notice Checks if a token is whitelisted.
     * @param token The address of the token to check
     * @return True if the token is whitelisted, false otherwise
     */
    function isTokenWhitelisted(address token) external view returns (bool);

    /**
     * @notice Whitelists a token for use in the container.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE.
     * @param token The address of the token to whitelist
     */
    function whitelistToken(address token) external;

    /**
     * @notice Removes a token from the whitelist.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE.
     * @param token The address of the token to blacklist
     */
    function blacklistToken(address token) external;

    /**
     * @notice Sets the dust threshold for a whitelisted token.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE.
     * @param token The address of the whitelisted token
     * @param threshold The minimum amount below which the token balance is considered dust
     */
    function setWhitelistedTokenDustThreshold(address token, uint256 threshold) external;

    /**
     * @notice Sets the swap router address.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE.
     * @param newSwapRouter The address of the new swap router contract
     */
    function setSwapRouter(address newSwapRouter) external;

    /**
     * @notice Prepares liquidity by executing swap instructions.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Executes swaps to prepare tokens for strategies.
     * @param instructions Array of swap instructions to execute
     */
    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata instructions) external;
}
