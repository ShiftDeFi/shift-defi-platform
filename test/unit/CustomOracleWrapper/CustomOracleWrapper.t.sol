// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {L1Base} from "test/L1Base.t.sol";
import {CustomOracleWrapper} from "contracts/priceOracles/CustomOracleWrapper.sol";

contract CustomOracleWrapperTest is L1Base {
    CustomOracleWrapper internal customOracleWrapper;

    bytes32 private constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    uint8 private constant DECIMALS = 8;

    function setUp() public virtual override {
        super.setUp();
        customOracleWrapper = new CustomOracleWrapper(roles.defaultAdmin, roles.configurator, roles.feederRole);
    }

    function test_WhitelistFeeder() public {
        assertFalse(
            AccessControl(customOracleWrapper).hasRole(FEEDER_ROLE, users.alice),
            "test_WhitelistFeeder: alice should not have feeder role initially"
        );

        vm.prank(roles.configurator);
        customOracleWrapper.whitelistFeeder(users.alice);
        assertTrue(
            AccessControl(customOracleWrapper).hasRole(FEEDER_ROLE, users.alice),
            "test_WhitelistFeeder: alice should have feeder role after whitelist"
        );
    }

    function test_RevertIf_WhitelistFeeder_NotOracleManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                ORACLE_MANAGER_ROLE
            )
        );
        customOracleWrapper.whitelistFeeder(users.bob);
    }

    function test_BlacklistFeeder() public {
        vm.prank(roles.configurator);
        customOracleWrapper.whitelistFeeder(users.alice);

        assertTrue(
            AccessControl(customOracleWrapper).hasRole(FEEDER_ROLE, users.alice),
            "test_BlacklistFeeder: alice should have feeder role after whitelist"
        );

        vm.prank(roles.configurator);
        customOracleWrapper.blacklistFeeder(users.alice);
        assertFalse(
            AccessControl(customOracleWrapper).hasRole(FEEDER_ROLE, users.alice),
            "test_BlacklistFeeder: alice should not have feeder role after blacklist"
        );
    }

    function test_RevertIf_BlacklistFeeder_NotOracleManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                ORACLE_MANAGER_ROLE
            )
        );
        customOracleWrapper.blacklistFeeder(users.bob);
    }

    function test_SubmitPrice() public {
        address token = address(dai);
        uint256 price = 123456;

        vm.prank(roles.configurator);
        customOracleWrapper.whitelistFeeder(users.alice);

        vm.prank(users.alice);
        customOracleWrapper.submitPrice(token, price);

        assertEq(customOracleWrapper.tokenToPrice(token), price, "test_SubmitPrice: token price mismatch");
    }

    function test_RevertIf_NotFeederRoleAndSubmitPrice() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), FEEDER_ROLE)
        );
        customOracleWrapper.submitPrice(address(1), 1);
    }

    function test_GetPrice() public {
        address token = address(dai);
        uint256 price = 123456;

        vm.prank(roles.configurator);
        customOracleWrapper.whitelistFeeder(users.alice);

        vm.prank(users.alice);
        customOracleWrapper.submitPrice(token, price);

        (uint256 actualPrice, uint8 actualDecimals) = customOracleWrapper.getPrice(token);
        assertEq(actualPrice, price, "test_GetPrice: price mismatch");
        assertEq(actualDecimals, DECIMALS, "test_GetPrice: decimals mismatch");
    }

    function test_Decimals() public view {
        assertEq(customOracleWrapper.decimals(), DECIMALS, "test_Decimals: decimals mismatch");
    }
}
