// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ISpookyPool {
    function depositV3Now(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 fillDeadlineOffset,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;
    function getCurrentTime() external view returns (uint256);
    function fillDeadlineBuffer() external view returns (uint32);
}
