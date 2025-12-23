// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceOracleAggregator {
    // ---- Events ----

    event PriceOracleSet(address indexed token, address indexed priceOracle);

    // ---- Errors ----

    error PriceOracleNotFound(address token);

    // ---- Functions ----

    /**
     * @notice Returns the price oracle address for a token.
     * @param token The address of the token
     * @return The address of the price oracle contract
     */
    function priceOracles(address token) external view returns (address);

    /**
     * @notice Fetches the normalized price of a token.
     * @param token The address of the token
     * @return The normalized price (8 decimals)
     */
    function fetchTokenPrice(address token) external view returns (uint256);

    /**
     * @notice Calculates the relative value of token0 in terms of token1 in unified decimals.
     * @param token0 The address of the first token
     * @param token1 The address of the second token
     * @param value0 The value of token0 to convert
     * @return The equivalent value in token1
     */
    function getRelativeValueUnified(address token0, address token1, uint256 value0) external view returns (uint256);

    /**
     * @notice Sets the price oracle for a token.
     * @dev Can only be called by accounts with ORACLE_MANAGER_ROLE.
     * @param token The address of the token
     * @param priceOracle The address of the price oracle contract
     */
    function setPriceOracle(address token, address priceOracle) external;
}
