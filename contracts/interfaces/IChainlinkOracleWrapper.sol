// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkOracleWrapper {
    event ChainlinkFeedSet(address indexed token, address indexed feed);
    error ChainlinkFeedNotFound(address token);

    function tokenToChainlinkFeed(address token) external view returns (address);
    function setChainlinkFeed(address token, address feed) external;
}
