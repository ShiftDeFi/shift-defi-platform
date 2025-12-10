// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkPriceFeed {
    // ---- Functions ----

    function latestAnswer() external view returns (int256);

    function decimals() external view returns (uint8);
}
