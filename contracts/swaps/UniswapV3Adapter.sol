// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IUniswapV3Router} from "../dependencies/interfaces/uniswapV3/IUniswapV3.sol";
import {IUniswapV3Adapter} from "../interfaces/IUniswapV3Adapter.sol";

contract UniswapV3Adapter is AccessControl, ReentrancyGuard, ISwapAdapter, IUniswapV3Adapter {
    using SafeERC20 for IERC20;

    bytes32 private constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    address public immutable uniswapV3Router;
    mapping(bytes => bool) public whitelistedPaths;
    constructor(address defaultAdmin, address _uniswapV3Router) {
        uniswapV3Router = _uniswapV3Router;
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    modifier onlyWhitelistManager() {
        require(hasRole(WHITELIST_MANAGER_ROLE, msg.sender), NotWhitelistManager(msg.sender));
        _;
    }

    function whitelistPath(address tokenIn, address tokenOut, uint24 fee) external onlyWhitelistManager {
        bytes memory path = abi.encodePacked(tokenIn, fee, tokenOut);
        whitelistedPaths[path] = true;
        emit PathWhitelisted(tokenIn, tokenOut, fee, path);
    }

    function blacklistPath(address tokenIn, address tokenOut, uint24 fee) external onlyWhitelistManager {
        bytes memory path = abi.encodePacked(tokenIn, fee, tokenOut);
        whitelistedPaths[path] = false;
        emit PathBlacklisted(tokenIn, tokenOut, fee, path);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes calldata data
    ) external payable override nonReentrant {
        require(whitelistedPaths[data], PathNotWhitelisted(data));

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(uniswapV3Router, amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        IUniswapV3Router(uniswapV3Router).exactInput(
            IUniswapV3Router.ExactInputParams({
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                path: data,
                recipient: address(this)
            })
        );
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        uint256 deltaTokenOut = balanceAfter - balanceBefore;
        require(deltaTokenOut >= minAmountOut, SlippageNotMet(tokenOut, deltaTokenOut, minAmountOut));
        IERC20(tokenOut).safeTransfer(receiver, deltaTokenOut);
    }
}
