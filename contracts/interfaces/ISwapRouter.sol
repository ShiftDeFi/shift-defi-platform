// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Interface for a universal token swap router (Exact-In model)
/// @notice Provides a unified interface for token swaps with fixed input amounts.
interface ISwapRouter {
    struct PredefinedSwapParameters {
        address adapter;
        bytes payload;
    }

    struct SwapInstruction {
        address adapter;
        address tokenIn; // Token to swap from
        address tokenOut; // Token to receive
        uint256 amountIn; // Exact amount of tokenIn to swap
        uint256 minAmountOut; // Minimum acceptable amount of tokenOut
        bytes payload; // Arbitrary data passed to router implementation
    }

    event SwapAdapterWhitelisted(address indexed adapter);
    event SwapAdapterBlacklisted(address indexed adapter);
    event Swap(
        address indexed caller,
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut
    );
    event DefaultAdapterForTokenPairSet(address indexed tokenIn, address indexed tokenOut, address indexed adapter);
    event PredefinedSwapParametersSet(
        address indexed tokenIn,
        address indexed tokenOut,
        address indexed adapter,
        bytes payload
    );

    error AdapterNotWhitelisted(address adapter);
    error NotWhitelistManager(address sender);
    error SlippageNotMet(uint256 amountOutBefore, uint256 amountOutAfter, uint256 minAmountOut);
    error DefaultAdapterNotSet(address tokenIn, address tokenOut);

    /// @notice Executes the swap based on the given instruction.
    /// @param instruction Details of the swap operation.
    /// @return amountOut Actual amount of tokenOut received.
    function swap(SwapInstruction calldata instruction) external payable returns (uint256 amountOut);
    function tryPredefinedSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (bool, uint256);
}
