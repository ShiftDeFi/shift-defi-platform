// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IMessageReceiver {
    // Decode raw message using MessagingLib library
    function receiveMessage(bytes memory rawMessage) external;
}
