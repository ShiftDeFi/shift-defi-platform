// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Common
/// @notice Decimal conversion helpers between token decimals and unified 18 decimals.
library Common {
    using Math for uint256;

    uint256 constant ONE = 1;
    uint8 constant UNIFIED_DECIMALS = 18;

    error DecimalsGt18(uint8 decimals);

    /**
     * @notice Converts an amount from token-native decimals to unified 18 decimals.
     * @param token Token address to read decimals from.
     * @param amount Amount in token-native decimals.
     * @return Amount scaled to 18 decimals.
     */
    function toUnifiedDecimalsUint8(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= UNIFIED_DECIMALS, DecimalsGt18(decimals));
        if (decimals == UNIFIED_DECIMALS) {
            return amount;
        }
        return amount.mulDiv(10 ** (UNIFIED_DECIMALS - decimals), ONE, Math.Rounding.Floor);
    }

    /**
     * @notice Converts an amount from unified 18 decimals to token-native decimals.
     * @param token Token address to read decimals from.
     * @param amount Amount in unified 18 decimals.
     * @return Amount scaled to token-native decimals.
     */
    function fromUnifiedDecimalsUint8(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= UNIFIED_DECIMALS, DecimalsGt18(decimals));
        if (decimals == UNIFIED_DECIMALS) {
            return amount;
        }
        return amount.mulDiv(ONE, 10 ** (UNIFIED_DECIMALS - decimals), Math.Rounding.Floor);
    }
}
