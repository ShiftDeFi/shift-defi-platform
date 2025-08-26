// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library Common {
    using Math for uint256;

    uint256 constant ONE = 1;
    uint8 constant UNIFIED_DECIMALS = 18;

    error DecimalsGt18(uint8 decimals);

    function toUnifiedDecimalsUint8(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= UNIFIED_DECIMALS, DecimalsGt18(decimals));
        if (decimals == UNIFIED_DECIMALS) {
            return amount;
        }
        return amount.mulDiv(10 ** (UNIFIED_DECIMALS - decimals), ONE, Math.Rounding.Floor);
    }

    function fromUnifiedDecimalsUint8(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= UNIFIED_DECIMALS, DecimalsGt18(decimals));
        if (decimals == UNIFIED_DECIMALS) {
            return amount;
        }
        return amount.mulDiv(ONE, 10 ** (UNIFIED_DECIMALS - decimals), Math.Rounding.Floor);
    }
}
