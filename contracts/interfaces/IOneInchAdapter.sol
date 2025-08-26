// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOneInchAdapter {
    error NotRouter(address sender);
    error InvalidSelector(bytes4 selector);
    error InvalidSourceToken(address token);
    error InvalidDestinationToken(address token);
    error InvalidAmountIn(uint256 amount);
    error InvalidMinAmountOut(uint256 amount);
    error InvalidSrcReceiver(address receiver);
}
