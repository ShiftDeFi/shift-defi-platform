// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ContainerMessagePackingLib} from "./ContainerMessagePackingLib.sol";

library WithdrawalRequestLib {
    using ContainerMessagePackingLib for ContainerMessagePackingLib.ContainerMessage;
    using ContainerMessagePackingLib for bytes;

    struct WithdrawalRequest {
        uint256 share;
    }

    function encode(WithdrawalRequest memory request) internal pure returns (bytes memory) {
        return
            ContainerMessagePackingLib
                .ContainerMessage({
                    type_: ContainerMessagePackingLib.WITHDRAWAL_REQUEST_TYPE,
                    payload: abi.encodePacked(request.share)
                })
                .encode();
    }

    function decodeContainerMessage(bytes memory rawMessage) internal pure returns (WithdrawalRequest memory request) {
        ContainerMessagePackingLib.ContainerMessage memory containerMessage = rawMessage.decode();
        require(
            containerMessage.type_ == ContainerMessagePackingLib.WITHDRAWAL_REQUEST_TYPE,
            ContainerMessagePackingLib.WrongMessageType(containerMessage.type_)
        );
        return decode(containerMessage.payload);
    }

    function decode(bytes memory payload) internal pure returns (WithdrawalRequest memory request) {
        uint256 share = abi.decode(payload, (uint256));
        return WithdrawalRequest({share: share});
    }
}
