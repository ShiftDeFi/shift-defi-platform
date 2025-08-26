// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IMessageAdapter {
    function router() external view returns (address);
    function send(uint256 chainTo, bytes memory params, bytes memory rawMessage) external payable;
}
