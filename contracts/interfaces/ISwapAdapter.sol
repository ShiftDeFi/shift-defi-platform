// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISwapAdapter {
    error SlippageCheckFailed(address token, uint256 amountOut, uint256 minAmountOut);

    /**
     * @notice Swap the input tokens for the output tokens.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to swap.
     * @param minAmountOut The minimum amount of output tokens to receive.
     * @param receiver The address to receive the output tokens.
     * @param data The data to pass to the adapter during the swap.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes memory data
    ) external payable;

    /**
     * @notice Preview the amount of output tokens that would be received for a given input amount.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to swap.
     * @param data The data to pass to the adapter during the swap.
     * @return amountOut The amount of output tokens that would be received.
     */
    function previewSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory data
    ) external view returns (uint256 amountOut);
}
