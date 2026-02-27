// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";

import {L1Base} from "test/L1Base.t.sol";

contract SwapRouterSwapTest is L1Base {
    address tokenIn;
    address tokenOut;

    function setUp() public virtual override {
        super.setUp();

        tokenIn = address(dai);
        tokenOut = address(notion);

        vm.prank(roles.defaultAdmin);
        AccessControl(address(swapRouter)).grantRole(WHITELIST_MANAGER_ROLE, roles.whitelistManager);
    }

    function _swapDaiToNotion(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        address adapter = address(mockSwapAdapter);
        bytes memory payload = hex"";

        ISwapRouter.SwapInstruction memory instruction = _craftSwapInstruction(
            adapter,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            payload
        );

        amountOut = swapRouter.swap(instruction);
    }

    function test_Swap() public {
        address adapter = address(mockSwapAdapter);
        uint256 amountIn = 123456;
        uint256 minAmountOut = 123456;

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        IERC20(tokenIn).approve(address(swapRouter), amountIn);
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(address(this));

        uint256 amountOut = _swapDaiToNotion(amountIn, minAmountOut);
        assertEq(amountOut, minAmountOut, "test_swap: must return minAmountOut");

        uint256 tokenInDelta = tokenInBalanceBefore - IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutDelta = IERC20(tokenOut).balanceOf(address(this)) - tokenOutBalanceBefore;
        assertEq(tokenInDelta, amountIn, "test_swap: must transfer amountIn from notion to mockSwapAdapter");
        assertGe(
            tokenOutDelta,
            minAmountOut,
            "test_swap: must transfer at least minAmountOut from mockSwapAdapter to dai"
        );
    }

    function test_RevertIf_NotWhitelistedAdapterAndSwap() public {
        address adapter = address(mockSwapAdapter);
        uint256 amountIn = 123456;
        uint256 minAmountOut = 123456;

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.AdapterNotWhitelisted.selector, adapter));
        _swapDaiToNotion(amountIn, minAmountOut);
    }

    function test_RevertIf_SlippageNotMetAndSwap() public {
        address adapter = address(mockSwapAdapter);
        uint256 amountIn = 1;
        uint256 minAmountOut = 5;

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.SlippageNotMet.selector, 0, 1, minAmountOut));
        _swapDaiToNotion(amountIn, minAmountOut);
    }

    function test_TryPredefinedSwap() public {
        address adapter = address(mockSwapAdapter);
        uint256 amountIn = 1;
        uint256 minAmountOut = 1;
        bytes memory payload = hex"0102030405060708090a0b0c0d0e0f10";

        ISwapRouter.SwapInstruction memory instruction = _craftSwapInstruction(
            adapter,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            payload
        );

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(instruction.adapter);

        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(
            instruction.tokenIn,
            instruction.tokenOut,
            instruction.adapter,
            instruction.payload
        );

        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        (bool success, uint256 amountOut) = swapRouter.tryPredefinedSwap(
            instruction.tokenIn,
            instruction.tokenOut,
            instruction.amountIn,
            instruction.minAmountOut
        );
        assertTrue(success, "test_tryPredefinedSwap: must return true");
        assertGe(amountOut, minAmountOut, "test_tryPredefinedSwap: must return 0");
    }
}
