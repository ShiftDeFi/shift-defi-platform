// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapAdapter} from "contracts/interfaces/ISwapAdapter.sol";

contract MockSwapAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    function previewSwap(address, address, uint256, bytes memory) external view override returns (uint256) {
        return 0;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        address receiver,
        bytes memory
    ) external payable override {
        if (amountIn > 0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenOut).safeTransfer(receiver, amountIn);
        }
    }
}
