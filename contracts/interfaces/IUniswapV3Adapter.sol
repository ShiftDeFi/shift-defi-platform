// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUniswapV3Adapter {
    event PathWhitelisted(address indexed tokenIn, address indexed tokenOut, uint24 fee, bytes path);
    event PathBlacklisted(address indexed tokenIn, address indexed tokenOut, uint24 fee, bytes path);

    error PathNotWhitelisted(bytes path);
    error NotWhitelistManager(address sender);

    function whitelistPath(address tokenIn, address tokenOut, uint24 fee) external;
    function blacklistPath(address tokenIn, address tokenOut, uint24 fee) external;
}
