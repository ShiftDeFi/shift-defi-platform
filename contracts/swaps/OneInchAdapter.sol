// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IOneInchAdapter} from "../interfaces/IOneInchAdapter.sol";
import {IOneInchV6} from "../dependencies/interfaces/oneInch/IOneInchV6.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OneInchAdapter is ReentrancyGuard, ISwapAdapter, IOneInchAdapter {
    using SafeERC20 for IERC20;

    address public immutable oneInchRouter;

    constructor(address _oneInchRouter) {
        oneInchRouter = _oneInchRouter;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes memory data
    ) external payable nonReentrant {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(oneInchRouter, amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);

        (bytes4 selector, bytes memory parameters) = abi.decode(data, (bytes4, bytes));
        if (selector == IOneInchV6.swap.selector) {
            (address executor, IOneInchV6.SwapDescription memory descs, bytes memory executorData) = abi.decode(
                parameters,
                (address, IOneInchV6.SwapDescription, bytes)
            );

            require(descs.srcToken == tokenIn, InvalidSourceToken(descs.srcToken));
            require(descs.dstToken == tokenOut, InvalidDestinationToken(descs.dstToken));
            require(descs.amount == amountIn, InvalidAmountIn(descs.amount));
            require(descs.minReturnAmount <= minAmountOut, InvalidMinAmountOut(descs.minReturnAmount));
            require(descs.dstReceiver == msg.sender, InvalidSrcReceiver(descs.srcReceiver));
            // TODO: add more executors and executor data
            IOneInchV6(oneInchRouter).swap(executor, descs, executorData);
        } else {
            // TODO: add more selectors
            revert InvalidSelector(selector);
        }

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(receiver);
        require(
            balanceAfter - balanceBefore >= minAmountOut,
            SlippageNotMet(tokenOut, balanceAfter - balanceBefore, minAmountOut)
        );
    }
}
