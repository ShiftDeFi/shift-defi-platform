// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {L1Base} from "test/L1Base.t.sol";

contract SwapRouterWhitelistTest is L1Base {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_RevertIf_WhitelistSwapAdapter_Unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                users.alice,
                WHITELIST_MANAGER_ROLE
            )
        );
        vm.prank(users.alice);
        swapRouter.whitelistSwapAdapter(address(1));
    }

    function test_WhitelistSwapAdapter() public {
        address adapter = address(1);

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        assertTrue(
            swapRouter.whitelistedAdapters(adapter),
            "test_whitelistSwapAdapter: must whitelist adapter successfully"
        );
    }

    function test_RevertIf_AlreadyWhitelistedAndWhitelistSwapAdapter() public {
        address adapter = address(1);

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        vm.expectRevert(Errors.AlreadyWhitelisted.selector);
        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);
    }

    function test_RevertIf_BlacklistSwapAdapter_Unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                users.alice,
                WHITELIST_MANAGER_ROLE
            )
        );
        vm.prank(users.alice);
        swapRouter.blacklistSwapAdapter(address(1));
    }

    function test_BlacklistSwapAdapter() public {
        address adapter = address(1);

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        vm.prank(roles.whitelistManager);
        swapRouter.blacklistSwapAdapter(adapter);

        assertFalse(
            swapRouter.whitelistedAdapters(adapter),
            "test_blacklistSwapAdapter: must blacklist adapter successfully"
        );
    }

    function test_RevertIf_AlreadyBlacklistedAndBlacklistSwapAdapter() public {
        vm.expectRevert(Errors.AlreadyBlacklisted.selector);
        vm.prank(roles.whitelistManager);
        swapRouter.blacklistSwapAdapter(address(1));
    }

    function test_SetPredefinedSwapParameters() public {
        address tokenIn = address(123);
        address tokenOut = address(234);
        address adapter = address(345);
        uint256 amountIn = 123;
        uint256 minAmountOut = 100;
        bytes memory payload = hex"0102030405060708090a0b0c0d0e0f10";

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);

        ISwapRouter.SwapInstruction memory instruction = _craftSwapInstruction(
            adapter,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            payload
        );

        (bool success, uint256 amountOut) = swapRouter.tryPredefinedSwap(
            instruction.tokenIn,
            instruction.tokenOut,
            instruction.amountIn,
            instruction.minAmountOut
        );
        assertFalse(success, "test_RevertIf_NotPredefinedAndTryPredefinedSwap: must return false");
        assertEq(amountOut, 0, "test_RevertIf_NotPredefinedAndTryPredefinedSwap: must return 0");

        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(tokenIn, tokenOut, adapter, payload);

        (address actualAdapter, bytes memory actualPayload) = swapRouter.predefinedSwapParameters(tokenIn, tokenOut);
        assertEq(actualAdapter, adapter, "test_setPredefinedSwapParameters: must set predefined adapter successfully");
        assertEq(actualPayload, payload, "test_setPredefinedSwapParameters: must set predefined payload successfully");
    }

    function test_RevertIf_ZeroAddressAndSetPredefinedSwapParameters() public {
        address someAddr = address(12345);
        bytes memory payload = hex"0102030405060708090a0b0c0d0e0f10";

        vm.prank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(someAddr);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(address(0), someAddr, someAddr, payload);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(someAddr, address(0), someAddr, payload);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(someAddr, someAddr, address(0), payload);
    }

    function test_RevertIf_NotWhitelistedAdapterAndSetPredefinedSwapParameters() public {
        address tokenIn = address(123);
        address tokenOut = address(234);
        address adapter = address(345);
        bytes memory payload = hex"0102030405060708090a0b0c0d0e0f10";

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.AdapterNotWhitelisted.selector, adapter));
        vm.prank(roles.whitelistManager);
        swapRouter.setPredefinedSwapParameters(tokenIn, tokenOut, adapter, payload);
    }

    function test_UnsetPredefinedSwapParameters() public {
        address tokenIn = address(123);
        address tokenOut = address(234);
        address adapter = address(345);
        bytes memory payload = hex"0102030405060708090a0b0c0d0e0f10";

        vm.startPrank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(adapter);
        swapRouter.setPredefinedSwapParameters(tokenIn, tokenOut, adapter, payload);
        vm.stopPrank();

        (address actualAdapter, bytes memory actualPayload) = swapRouter.predefinedSwapParameters(tokenIn, tokenOut);

        assertEq(
            actualAdapter,
            adapter,
            "test_unsetPredefinedSwapParameters: must set predefined adapter successfully"
        );
        assertEq(
            actualPayload,
            payload,
            "test_unsetPredefinedSwapParameters: must set predefined payload successfully"
        );

        vm.prank(roles.whitelistManager);
        swapRouter.unsetPredefinedSwapParameters(tokenIn, tokenOut);

        (actualAdapter, actualPayload) = swapRouter.predefinedSwapParameters(tokenIn, tokenOut);
        assertEq(
            actualAdapter,
            address(0),
            "test_unsetPredefinedSwapParameters: must unset predefined adapter successfully"
        );
        assertEq(
            actualPayload,
            bytes(""),
            "test_unsetPredefinedSwapParameters: must unset predefined payload successfully"
        );
    }

    function test_RevertIf_UnsetPredefinedSwapParameters_NotSet() public {
        address tokenIn = address(123);
        address tokenOut = address(234);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapRouter.SwapParametersNotSetForTokenPair.selector, tokenIn, tokenOut)
        );
        vm.prank(roles.whitelistManager);
        swapRouter.unsetPredefinedSwapParameters(tokenIn, tokenOut);
    }
}
