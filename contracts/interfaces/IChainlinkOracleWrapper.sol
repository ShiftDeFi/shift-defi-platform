// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkOracleWrapper {
    // ---- Events ----

    event ChainlinkFeedSet(address indexed token, address indexed feed);

    // ---- Errors ----

    error ChainlinkFeedNotFound(address token);
    error ZeroPrice(address token);

    // ---- Functions ----

    function tokenToChainlinkFeed(address token) external view returns (address);

    function setChainlinkFeed(address token, address feed) external;
}
