// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkOracleWrapper {
    // ---- Events ----

    event ChainlinkFeedSet(address indexed token, address indexed feed);

    // ---- Errors ----

    error ChainlinkFeedNotFound(address token);
    error ZeroPrice(address token);

    // ---- Functions ----

    /**
     * @notice Returns the Chainlink feed address for a token.
     * @param token The address of the token
     * @return The address of the Chainlink price feed
     */
    function tokenToChainlinkFeed(address token) external view returns (address);

    /**
     * @notice Sets the Chainlink feed address for a token.
     * @dev Can only be called by accounts with ORACLE_MANAGER_ROLE.
     * @param token The address of the token
     * @param feed The address of the Chainlink price feed
     */
    function setChainlinkFeed(address token, address feed) external;
}
