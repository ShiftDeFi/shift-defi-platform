// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {MockContainer} from "test/mocks/MockContainer.sol";
import {MockSwapRouter} from "test/mocks/MockSwapRouter.sol";

import {L1Base} from "test/L1Base.t.sol";

contract ContainerTest is L1Base {
    MockContainer internal container;

    error TokenValidationFailed(address token);

    function setUp() public override {
        super.setUp();
        container = new MockContainer(roles.defaultAdmin, roles.tokenManager, address(notion), address(swapRouter));
    }

    function test_WhitelistToken() public {
        _whitelistToken(address(container), address(notion));
        container.validateToken(address(notion));

        assertEq(container.isTokenWhitelisted(address(notion)), true);
        assertEq(IERC20(notion).allowance(address(container), address(swapRouter)), type(uint256).max);
    }

    function test_RevertIf_WhitelistTokenToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.tokenManager);
        container.whitelistToken(address(0));
    }

    function test_RevertIf_WhitelistTokenAlreadyWhitelisted() public {
        _whitelistToken(address(container), address(notion));
        vm.expectRevert(IContainer.AlreadyWhitelistedToken.selector);
        vm.prank(roles.tokenManager);
        container.whitelistToken(address(notion));
    }

    function test_BlacklistToken() public {
        _whitelistToken(address(container), address(notion));

        vm.prank(roles.tokenManager);
        container.blacklistToken(address(notion));

        assertEq(container.isTokenWhitelisted(address(notion)), false);
        assertEq(IERC20(notion).allowance(address(container), address(swapRouter)), 0);
    }

    function test_RevertIf_BlacklistTokenToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.tokenManager);
        container.blacklistToken(address(0));
    }

    function test_RevertIf_BlacklistTokenNotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(notion)));
        vm.prank(roles.tokenManager);
        container.blacklistToken(address(notion));
    }

    function test_RevertIf_SetWhitelistedTokenDustThresholdToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.tokenManager);
        container.setWhitelistedTokenDustThreshold(address(0), 1);
    }

    function test_RevertIf_SetWhitelistedTokenDustThresholdToZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(roles.tokenManager);
        container.setWhitelistedTokenDustThreshold(address(notion), 0);
    }

    function test_RevertIf_SetWhitelistedTokenDustThresholdToNotWhitelistedToken() public {
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(notion)));
        vm.prank(roles.tokenManager);
        container.setWhitelistedTokenDustThreshold(address(notion), 1);
    }

    function test_ValidateWhitelistedTokensBeforeReport() public {
        _whitelistToken(address(container), address(notion));
        vm.prank(roles.tokenManager);

        uint256 dustThreshold = vault.minDepositAmount();
        vm.prank(roles.tokenManager);
        container.setWhitelistedTokenDustThreshold(address(notion), dustThreshold);

        notion.mint(address(container), dustThreshold + 1);
        assertEq(
            container.validateWhitelistedTokensBeforeReport(true, true),
            true,
            "test_ValidateWhitelistedTokensBeforeReport: notion not ignored"
        );
        assertEq(
            container.validateWhitelistedTokensBeforeReport(false, true),
            false,
            "test_ValidateWhitelistedTokensBeforeReport: notion dust not ignored"
        );

        _whitelistToken(address(container), address(dai));

        vm.prank(roles.tokenManager);
        container.setWhitelistedTokenDustThreshold(address(dai), dustThreshold);

        dai.mint(address(container), dustThreshold);

        assertEq(
            container.validateWhitelistedTokensBeforeReport(true, false),
            false,
            "test_ValidateWhitelistedTokensBeforeReport: any balance must be ignored"
        );
        assertEq(
            container.validateWhitelistedTokensBeforeReport(true, true),
            true,
            "test_ValidateWhitelistedTokensBeforeReport: dai dust not ignored"
        );

        dai.mint(address(container), 1);

        assertEq(
            container.validateWhitelistedTokensBeforeReport(true, true),
            false,
            "test_ValidateWhitelistedTokensBeforeReport: dai balance over dust threshold ignored"
        );
    }

    function test_HasOnlyNotionToken() public {
        _whitelistToken(address(container), address(notion));

        assertEq(container.hasOnlyNotionToken(), false);
        notion.mint(address(container), 1);
        assertEq(container.hasOnlyNotionToken(), true);
    }

    function test_DropApprovesFromWhitelistedTokens() public {
        _whitelistToken(address(container), address(notion));
        container.dropApprovesFromWhitelistedTokens(address(swapRouter));
        assertEq(IERC20(notion).allowance(address(container), address(swapRouter)), 0);
    }

    function test_ApproveWhitelistedTokens() public {
        _whitelistToken(address(container), address(notion));
        container.approveWhitelistedTokens(address(swapRouter));
        assertEq(IERC20(notion).allowance(address(container), address(swapRouter)), type(uint256).max);
    }

    function test_DropApprovesFromOldSwapRouter() public {
        address newSwapRouter = address(new MockSwapRouter());
        vm.prank(roles.tokenManager);
        container.setSwapRouter(newSwapRouter);

        assertEq(IERC20(notion).allowance(address(container), address(swapRouter)), 0);
    }

    function test_RevertIf_SetSwapRouterToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.tokenManager);
        container.setSwapRouter(address(0));
    }
}
