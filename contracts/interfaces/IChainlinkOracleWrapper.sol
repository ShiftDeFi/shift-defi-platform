// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkOracleWrapper {
    // ---- Events ----

    event ChainlinkFeedSet(address indexed token, address indexed feed);
    event PriceFeedStalenessThresholdUpdated(uint256 previousThreshold, uint256 newThreshold);

    // ---- Errors ----

    error ChainlinkFeedNotFound(address token);
    error ZeroPrice(address token);
    error ZeroStalenessThreshold();
    error StalePriceFeed(address token, uint256 updatedAt, uint256 threshold);

    // ---- Functions ----

    /**
     * @notice Returns the Chainlink feed address for a token.
     * @param token The address of the token
     * @return The address of the Chainlink price feed
     */
    function tokenToChainlinkFeed(address token) external view returns (address);

    /**
     * @notice Returns the maximum age (in seconds) a price update may have before it is considered stale.
     */
    function priceFeedStalenessThreshold() external view returns (uint256);

    /**
     * @notice Sets the Chainlink feed address for a token.
     * @dev Can only be called by accounts with ORACLE_MANAGER_ROLE.
     * @param token The address of the token
     * @param feed The address of the Chainlink price feed
     */
    function setChainlinkFeed(address token, address feed) external;

    /**
     * @notice Sets the maximum age a Chainlink price update may have before it is considered stale.
     * @dev Can only be called by accounts with ORACLE_MANAGER_ROLE.
     * @param threshold Maximum age in seconds
     */
    function setPriceFeedStalenessThreshold(uint256 threshold) external;
}
