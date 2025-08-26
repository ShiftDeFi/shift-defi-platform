// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {AddressArrayPackingLib} from "./AddressArrayPackingLib.sol";
import {ContainerMessagePackingLib} from "./ContainerMessagePackingLib.sol";

library WithdrawalResponseLib {
    using AddressArrayPackingLib for address[];
    using AddressArrayPackingLib for bytes;
    using ContainerMessagePackingLib for ContainerMessagePackingLib.ContainerMessage;
    using ContainerMessagePackingLib for bytes;

    struct WithdrawalResponse {
        address[] tokens;
        uint256[] amounts;
    }

    function encode(WithdrawalResponse memory response) internal pure returns (bytes memory) {
        bytes memory payload = abi.encode(response.tokens.packAddresses(), response.amounts);
        return
            ContainerMessagePackingLib
                .ContainerMessage({type_: ContainerMessagePackingLib.WITHDRAWAL_RESPONSE_TYPE, payload: payload})
                .encode();
    }

    function decodeContainerMessage(
        bytes memory rawMessage
    ) internal pure returns (WithdrawalResponse memory response) {
        ContainerMessagePackingLib.ContainerMessage memory containerMessage = rawMessage.decode();
        require(
            containerMessage.type_ == ContainerMessagePackingLib.WITHDRAWAL_RESPONSE_TYPE,
            ContainerMessagePackingLib.WrongMessageType(containerMessage.type_)
        );
        return decode(containerMessage.payload);
    }

    function decode(bytes memory payload) internal pure returns (WithdrawalResponse memory response) {
        (bytes memory packedAddresses, uint256[] memory amounts) = abi.decode(payload, (bytes, uint256[]));
        return WithdrawalResponse({tokens: packedAddresses.unpackAddresses(), amounts: amounts});
    }
}
