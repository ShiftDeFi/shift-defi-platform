// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "./helpers/Errors.sol";

library AddressArrayPackingLib {
    function packAddresses(address[] memory addresses) internal pure returns (bytes memory) {
        bytes memory result = new bytes(20 * addresses.length);
        for (uint i = 0; i < addresses.length; ) {
            assembly {
                let offset := add(add(result, 32), mul(i, 20)) // find pointer to address position
                mstore(offset, shl(96, mload(add(add(addresses, 32), mul(i, 32))))) // save address value to bytes array
                i := add(i, 1) // increment index
            }
        }
        return result;
    }

    function unpackAddresses(bytes memory data) internal pure returns (address[] memory) {
        // TODO: move to utils lib
        require(data.length % 20 == 0, Errors.InvalidDataLength());
        uint count = data.length / 20;
        address[] memory addresses = new address[](count);

        for (uint i = 0; i < count; ) {
            address addr;
            assembly {
                addr := mload(add(add(data, 20), mul(i, 20)))
            }
            addresses[i] = addr;
            unchecked {
                i++;
            }
        }

        return addresses;
    }
}
