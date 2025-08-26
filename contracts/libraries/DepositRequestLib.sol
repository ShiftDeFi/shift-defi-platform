// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {AddressArrayPackingLib} from "./AddressArrayPackingLib.sol";
import {ContainerMessagePackingLib} from "./ContainerMessagePackingLib.sol";

library DepositRequestLib {
    using AddressArrayPackingLib for address[];
    using AddressArrayPackingLib for bytes;
    using ContainerMessagePackingLib for ContainerMessagePackingLib.ContainerMessage;
    using ContainerMessagePackingLib for bytes;

    struct DepositRequest {
        address[] tokens;
        uint256[] amounts;
    }

    function encode(DepositRequest memory request) internal pure returns (bytes memory) {
        bytes memory payload = abi.encode(request.tokens.packAddresses(), request.amounts);
        return
            ContainerMessagePackingLib
                .ContainerMessage({type_: ContainerMessagePackingLib.DEPOSIT_REQUEST_TYPE, payload: payload})
                .encode();
    }

    function decodeContainerMessage(bytes memory rawMessage) internal pure returns (DepositRequest memory request) {
        ContainerMessagePackingLib.ContainerMessage memory containerMessage = rawMessage.decode();
        require(
            containerMessage.type_ == ContainerMessagePackingLib.DEPOSIT_REQUEST_TYPE,
            ContainerMessagePackingLib.WrongMessageType(containerMessage.type_)
        );
        return decode(containerMessage.payload);
    }

    function decode(bytes memory payload) internal pure returns (DepositRequest memory request) {
        (bytes memory packedAddresses, uint256[] memory amounts) = abi.decode(payload, (bytes, uint256[]));
        return DepositRequest({tokens: packedAddresses.unpackAddresses(), amounts: amounts});
    }
}
