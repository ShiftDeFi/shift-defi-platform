// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceOracleAggregator {
    event PriceOracleSet(address indexed token, address indexed priceOracle);
    error PriceOracleNotFound(address token, address priceOracle);

    function priceOracles(address token) external view returns (address);
    function fetchTokenPrice(address token) external view returns (uint256);
    function getRelativeValueUnified(address token0, address token1, uint256 value0) external view returns (uint256);

    function setPriceOracle(address token, address priceOracle) external;
}
