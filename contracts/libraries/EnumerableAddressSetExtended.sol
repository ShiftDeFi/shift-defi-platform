// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title EnumerableAddressSetExtended
/// @notice Helper to fetch index of an address inside EnumerableSet.
library EnumerableAddressSetExtended {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Returns whether a value exists in the set and its index.
     * @dev Index is zero-based when found. If not found, returns (false, 0).
     * @param set Storage set reference.
     * @param value Address to look up.
     * @return found True if present.
     * @return index Zero-based index when found; undefined if not found.
     */
    function indexOf(
        EnumerableSet.AddressSet storage set,
        address value
    ) internal view returns (bool found, uint256 index) {
        uint256 i = set._inner._positions[bytes32(uint256(uint160(value)))];
        if (i == 0) return (false, 0);
        return (true, i - 1);
    }
}
