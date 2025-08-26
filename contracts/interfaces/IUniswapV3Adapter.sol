// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUniswapV3Adapter {
    error PathNotWhitelisted(bytes path);
    error NotWhitelistManager(address sender);

    function whitelistPath(address tokenIn, address tokenOut, uint24 fee) external;
    function blacklistPath(address tokenIn, address tokenOut, uint24 fee) external;
}
