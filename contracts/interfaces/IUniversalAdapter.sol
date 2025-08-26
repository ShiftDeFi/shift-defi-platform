// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUniversalAdapter {
    struct SwapInfo {
        address router;
        uint256 amountIndex;
        bytes payload;
    }

    event SwapInfoSet(address indexed fromToken, address indexed toToken, SwapInfo swapInfo);

    error NotWhitelistManager(address sender);
    error NoSwapInfo(address fromToken, address toToken);

    function isSwapSupported(address tokenIn, address tokenOut) external view returns (bool);
    function setSwapInfo(
        address fromToken,
        address toToken,
        address router,
        uint256 amountIndex,
        bytes calldata payload
    ) external;
}
