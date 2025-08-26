// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOneInchV6 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }
    function swap(address executor, SwapDescription memory descs, bytes memory data) external payable;
}
