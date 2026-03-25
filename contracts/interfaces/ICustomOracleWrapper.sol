// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICustomOracleWrapper {
    event PriceSubmitted(address indexed token, uint256 price);

    /**
     * @notice Submits a price for a token.
     * @dev Can only be called by accounts with FEEDER_ROLE.
     * @param token The address of the token.
     * @param price The price to submit.
     */
    function submitPrice(address token, uint256 price) external;
}
