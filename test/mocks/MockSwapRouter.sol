// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockSwapRouter is ISwapRouter {
    function swap(SwapInstruction calldata instruction) external payable override returns (uint256) {
        IERC20(instruction.tokenIn).transferFrom(msg.sender, address(this), instruction.amountIn);
        IERC20(instruction.tokenOut).transfer(msg.sender, instruction.minAmountOut + 1);
        return instruction.minAmountOut;
    }

    function tryPredefinedSwap(address, address, uint256, uint256) external payable returns (bool, uint256) {}

    function whitelistSwapAdapter(address) external {}

    function blacklistSwapAdapter(address) external {}

    function setPredefinedSwapParameters(address, address, address, bytes calldata) external {}

    function whitelistedAdapters(address) external view returns (bool) {}

    function predefinedSwapParameters(address, address) external view returns (address, bytes memory) {}
}
