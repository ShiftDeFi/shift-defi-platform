// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISwapAdapter {
    error SlippageNotMet(address token, uint256 amountOut, uint256 minAmountOut);

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes memory data
    ) external payable;
}
