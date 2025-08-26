// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library EnumerableAddressSetExtended {
    using EnumerableSet for EnumerableSet.AddressSet;

    function indexOf(
        EnumerableSet.AddressSet storage set,
        address value
    ) internal view returns (bool found, uint256 index) {
        uint256 i = set._inner._positions[bytes32(uint256(uint160(value)))];
        if (i == 0) return (false, 0);
        return (true, i - 1);
    }
}
