// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
interface ICustomOracleWrapper {
    event PriceSubmitted(address indexed token, uint256 price);
    function submitPrice(address token, uint256 price) external;
}
