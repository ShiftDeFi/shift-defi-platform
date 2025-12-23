// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICustomOracleWrapper {
    event PriceSubmitted(address indexed token, uint256 price);

    /**
     * @notice Grants FEEDER_ROLE to an address, allowing it to submit prices.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param feeder The address to grant FEEDER_ROLE to.
     */
    function whitelistFeeder(address feeder) external;

    /**
     * @notice Revokes FEEDER_ROLE from an address, preventing it from submitting prices.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param feeder The address to revoke FEEDER_ROLE from.
     */
    function blacklistFeeder(address feeder) external;

    /**
     * @notice Submits a price for a token.
     * @dev Can only be called by accounts with FEEDER_ROLE.
     * @param token The address of the token.
     * @param price The price to submit.
     */
    function submitPrice(address token, uint256 price) external;
}
