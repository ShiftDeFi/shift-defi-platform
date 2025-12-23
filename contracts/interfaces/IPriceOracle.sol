// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPriceOracle {
    // ---- Functions ----

    /**
     * @notice Gets the price of a token.
     * @param token The address of the token
     * @return The price of the token
     * @return The number of decimals for the price
     */
    function getPrice(address token) external view returns (uint256, uint8);

    /**
     * @notice Returns the number of decimals used for prices.
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);
}
