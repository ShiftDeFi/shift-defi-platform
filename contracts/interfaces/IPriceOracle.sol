// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256, uint8);
    function decimals() external view returns (uint8);
}
