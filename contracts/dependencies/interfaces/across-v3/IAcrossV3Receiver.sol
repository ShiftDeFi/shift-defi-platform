// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ISpookyPool} from "./ISpookyPool.sol";

interface IAcrossV3Receiver {
    struct AcrossParams {
        address exclusiveRelayer;
        uint32 fillDeadline;
        uint32 exclusiveDeadline;
        uint256 fee;
    }

    event SpookyPoolUpdated(address old, address new_);
    event FeeCapPctUpdated(uint256 old, uint256 new_);

    error DeadlineExceeded(uint32 currentTimestamp, uint256 timestamp);
    error OnlySpookyPool(address addr, address spookyPool);
    error FeeTooHigh(uint256 fee);
    error InvalidFeeCapPct(uint256 feeCapPct);
    error MinTokenAmountTooLow(uint256 amount, uint256 fee, uint256 minTokenAmount);

    function spookyPool() external view returns (address);
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external;
}
