// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {AddressArrayPackingLib} from "./AddressArrayPackingLib.sol";
import {ContainerMessagePackingLib} from "./ContainerMessagePackingLib.sol";

library DepositResponseLib {
    using AddressArrayPackingLib for address[];
    using AddressArrayPackingLib for bytes;
    using ContainerMessagePackingLib for ContainerMessagePackingLib.ContainerMessage;
    using ContainerMessagePackingLib for bytes;

    struct DepositResponse {
        address[] tokens;
        uint256[] amounts;
        uint256 navAH;
        uint256 navAE;
    }

    function encode(DepositResponse memory response) internal pure returns (bytes memory) {
        bytes memory payload = abi.encode(
            response.tokens.packAddresses(),
            response.amounts,
            response.navAH,
            response.navAE
        );
        return
            ContainerMessagePackingLib
                .ContainerMessage({type_: ContainerMessagePackingLib.DEPOSIT_RESPONSE_TYPE, payload: payload})
                .encode();
    }

    function decodeContainerMessage(bytes memory rawMessage) internal pure returns (DepositResponse memory response) {
        ContainerMessagePackingLib.ContainerMessage memory containerMessage = rawMessage.decode();
        require(
            containerMessage.type_ == ContainerMessagePackingLib.DEPOSIT_RESPONSE_TYPE,
            ContainerMessagePackingLib.WrongMessageType(containerMessage.type_)
        );
        return decode(containerMessage.payload);
    }

    function decode(bytes memory payload) internal pure returns (DepositResponse memory response) {
        (bytes memory packedAddresses, uint256[] memory amounts, uint256 navAH, uint256 navAE) = abi.decode(
            payload,
            (bytes, uint256[], uint256, uint256)
        );
        return
            DepositResponse({tokens: packedAddresses.unpackAddresses(), amounts: amounts, navAH: navAH, navAE: navAE});
    }
}
