// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "./helpers/Errors.sol";

library ContainerMessagePackingLib {
    struct ContainerMessage {
        uint8 type_;
        bytes payload;
    }

    uint256 constant MAXIMUM_PAYLOAD_LENGTH = 100000;

    uint8 constant DEPOSIT_REQUEST_TYPE = 0;
    uint8 constant WITHDRAWAL_REQUEST_TYPE = 2;
    uint8 constant DEPOSIT_RESPONSE_TYPE = 1;
    uint8 constant WITHDRAWAL_RESPONSE_TYPE = 3;

    error WrongMessageType(uint8);

    function encode(ContainerMessage memory message) internal pure returns (bytes memory) {
        _validateMessageType(message.type_);
        require(message.payload.length <= MAXIMUM_PAYLOAD_LENGTH, Errors.InvalidDataLength());
        return abi.encodePacked(message.type_, message.payload);
    }

    function decode(bytes memory data) internal pure returns (ContainerMessage memory message) {
        require(data.length > 1, Errors.InvalidDataLength());
        message.type_ = uint8(data[0]);
        _validateMessageType(message.type_);
        bytes memory payload;
        assembly {
            payload := add(data, 1) // move pointer to payload
            mstore(payload, sub(mload(data), 1)) // Устанавливаем длину data
        }
        require(payload.length < MAXIMUM_PAYLOAD_LENGTH, Errors.InvalidDataLength());
        message.payload = payload;
    }

    function _validateMessageType(uint8 type_) private pure {
        if (
            (type_ != DEPOSIT_REQUEST_TYPE) &&
            (type_ != WITHDRAWAL_REQUEST_TYPE) &&
            (type_ != DEPOSIT_RESPONSE_TYPE) &&
            (type_ != WITHDRAWAL_RESPONSE_TYPE)
        ) {
            revert WrongMessageType(type_);
        }
    }
}
