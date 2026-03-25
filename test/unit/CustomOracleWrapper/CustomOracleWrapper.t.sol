// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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

    function test_SubmitPrice() public {
        address token = address(dai);
        uint256 price = 123456;

        vm.prank(roles.feederRole);
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

        vm.prank(roles.feederRole);
        customOracleWrapper.submitPrice(token, price);

        (uint256 actualPrice, uint8 actualDecimals) = customOracleWrapper.getPrice(token);
        assertEq(actualPrice, price, "test_GetPrice: price mismatch");
        assertEq(actualDecimals, DECIMALS, "test_GetPrice: decimals mismatch");
    }

    function test_Decimals() public view {
        assertEq(customOracleWrapper.decimals(), DECIMALS, "test_Decimals: decimals mismatch");
    }
}
