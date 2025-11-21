// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IMessageReceiver {
    function receiveMessage(bytes memory rawMessage) external;
}
