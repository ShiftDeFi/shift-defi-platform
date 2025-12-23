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

    // ---- Functions ----

    /**
     * @notice Executes a token swap based on the provided instruction.
     * @dev The adapter must be whitelisted. Transfers tokens from the caller and returns output tokens.
     *      Reverts if the actual output amount is less than `minAmountOut`.
     * @param instruction Swap instruction containing adapter, tokens, amounts, and payload.
     * @return amountOut Actual amount of output tokens received after the swap.
     */
    function swap(SwapInstruction calldata instruction) external payable returns (uint256 amountOut);

    /**
     * @notice Attempts to execute a swap using predefined parameters for a token pair.
     * @dev Returns false if no predefined parameters exist for the pair. Otherwise executes swap and returns true with amount.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn Exact amount of input tokens to swap.
     * @param minAmountOut Minimum acceptable amount of output tokens.
     * @return success True if predefined parameters exist and swap was executed, false otherwise.
     * @return amountOut Actual amount of output tokens received (0 if success is false).
     */
    function tryPredefinedSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (bool success, uint256 amountOut);

    /**
     * @notice Whitelists a swap adapter.
     * @dev Can only be called by accounts with WHITELIST_MANAGER_ROLE.
     * @param adapter The address of the swap adapter to whitelist.
     */
    function whitelistSwapAdapter(address adapter) external;

    /**
     * @notice Blacklists a swap adapter.
     * @dev Can only be called by accounts with WHITELIST_MANAGER_ROLE.
     * @param adapter The address of the swap adapter to blacklist.
     */
    function blacklistSwapAdapter(address adapter) external;

    /**
     * @notice Sets predefined swap parameters for a token pair.
     * @dev Can only be called by accounts with WHITELIST_MANAGER_ROLE. The adapter must be whitelisted.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param adapter The address of the swap adapter to use for this pair.
     * @param payload The payload to pass to the adapter during swaps.
     */
    function setPredefinedSwapParameters(
        address tokenIn,
        address tokenOut,
        address adapter,
        bytes calldata payload
    ) external;

    /**
     * @notice Returns the whitelist status of a swap adapter.
     * @param adapter The address of the swap adapter to check.
     * @return True if the adapter is whitelisted, false otherwise.
     */
    function whitelistedAdapters(address adapter) external view returns (bool);

    /**
     * @notice Returns the predefined swap parameters for a token pair.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @return adapter The adapter address configured for this pair.
     * @return payload The payload configured for this pair.
     */
    function predefinedSwapParameters(
        address tokenIn,
        address tokenOut
    ) external view returns (address adapter, bytes memory payload);
}
