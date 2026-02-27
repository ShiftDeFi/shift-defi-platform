// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IMessageAdapter} from "contracts/interfaces/IMessageAdapter.sol";

contract MockMessageAdapter is IMessageAdapter {
    function router() external view override returns (address) {}

    function send(uint256, bytes memory, bytes memory) external payable override {}
}
