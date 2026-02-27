// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IPriceOracleAggregator} from "contracts/interfaces/IPriceOracleAggregator.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {L1Base} from "test/L1Base.t.sol";
import {MockPriceOracle} from "test/mocks/MockPriceOracle.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract PriceOracleAggregatorTest is L1Base {
    IPriceOracleAggregator internal priceOracleAggregator;

    MockPriceOracle internal mockPriceOracle;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function setUp() public override {
        super.setUp();
        priceOracleAggregator = _deployPriceOracleAggregator();
        mockPriceOracle = new MockPriceOracle(8);
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 6);
    }

    function test_SetPriceOracle() public {
        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(dai), address(1));

        assertEq(
            priceOracleAggregator.priceOracles(address(dai)),
            address(1),
            "test_SetPriceOracle: price oracle not set"
        );
    }

    function test_RevertIf_NotOracleManagerAndSetPriceOracle() public {
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                users.alice,
                ORACLE_MANAGER_ROLE
            )
        );
        priceOracleAggregator.setPriceOracle(address(dai), address(1));
    }

    function test_RevertIf_ZeroAddressAndSetPriceOracle() public {
        vm.prank(roles.oracleManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        priceOracleAggregator.setPriceOracle(address(0), address(1));

        vm.prank(roles.oracleManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        priceOracleAggregator.setPriceOracle(address(1), address(0));
    }

    function test_FetchTokenPriceDefaultDecimals() public {
        address token = address(dai);
        uint256 price = 12345678;
        mockPriceOracle.setPrice(token, price);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(token, address(mockPriceOracle));

        uint256 actualPrice = priceOracleAggregator.fetchTokenPrice(token);
        assertEq(actualPrice, price, "test_FetchTokenPriceDefaultDecimals: price mismatch");
    }

    function test_FetchTokenPriceSmallDecimals() public {
        address token = address(dai);

        mockPriceOracle.setPrice(token, 123456);
        mockPriceOracle.setDecimals(6);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(token, address(mockPriceOracle));

        uint256 actualPrice = priceOracleAggregator.fetchTokenPrice(token);
        assertEq(actualPrice, 12345600, "test_FetchTokenPriceSmallDecimals: price mismatch");
    }

    function test_FetchTokenPriceLargeDecimals() public {
        address token = address(dai);

        mockPriceOracle.setPrice(token, 123456);
        mockPriceOracle.setDecimals(10);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(token, address(mockPriceOracle));

        uint256 actualPrice = priceOracleAggregator.fetchTokenPrice(token);
        assertEq(actualPrice, 1234, "test_FetchTokenPriceLargeDecimals: price mismatch");
    }

    function test_RevertIf_ZeroAddressAndFetchTokenPrice() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        priceOracleAggregator.fetchTokenPrice(address(0));
    }

    function test_RevertIf_PriceOracleNotFoundAndFetchTokenPrice() public {
        vm.expectRevert(abi.encodeWithSelector(IPriceOracleAggregator.PriceOracleNotFound.selector, address(dai)));
        priceOracleAggregator.fetchTokenPrice(address(dai));
    }

    function test_GetRelativeValueUnifiedT0T1() public {
        mockPriceOracle.setPrice(address(token0), 2e8);
        mockPriceOracle.setPrice(address(token1), 1e8);

        vm.startPrank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));
        priceOracleAggregator.setPriceOracle(address(token1), address(mockPriceOracle));
        vm.stopPrank();

        uint256 result = priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);
        assertEq(result, 2e18, "test_GetRelativeValueUnifiedT0T1: result mismatch");
    }

    function test_GetRelativeValueUnifiedT1T0() public {
        mockPriceOracle.setPrice(address(token0), 2e8);
        mockPriceOracle.setPrice(address(token1), 1e8);

        vm.startPrank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));
        priceOracleAggregator.setPriceOracle(address(token1), address(mockPriceOracle));
        vm.stopPrank();

        uint256 result = priceOracleAggregator.getRelativeValueUnified(address(token1), address(token0), 1e6);
        assertEq(result, 5e17, "test_GetRelativeValueUnifiedT1T0: result mismatch");
    }

    function test_GetRelativeValueUnifiedSameDecimals() public {
        // Set both tokens to 18 decimals
        token0.setDecimals(18);
        token1.setDecimals(18);

        // token0: $3, token1: $1
        // 1 token0 ($3) = 3 token1 ($1 each)
        mockPriceOracle.setPrice(address(token0), 3e8);
        mockPriceOracle.setPrice(address(token1), 1e8);

        vm.startPrank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));
        priceOracleAggregator.setPriceOracle(address(token1), address(mockPriceOracle));
        vm.stopPrank();

        uint256 result = priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);
        assertEq(result, 3e18, "test_GetRelativeValueUnifiedSameDecimals: result mismatch");
    }

    function test_GetRelativeValueUnifiedZeroValue() public {
        mockPriceOracle.setPrice(address(token0), 2e8);
        mockPriceOracle.setPrice(address(token1), 1e8);

        vm.startPrank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));
        priceOracleAggregator.setPriceOracle(address(token1), address(mockPriceOracle));
        vm.stopPrank();

        uint256 result = priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 0);
        assertEq(result, 0, "test_GetRelativeValueUnifiedZeroValue: result mismatch");
    }

    function test_GetRelativeValueUnifiedT0T0() public {
        mockPriceOracle.setPrice(address(token0), 1e8);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));

        uint256 result = priceOracleAggregator.getRelativeValueUnified(address(token0), address(token0), 1e18);
        assertEq(result, 1e18, "test_GetRelativeValueUnifiedT0T0: result mismatch");
    }

    function test_RevertIf_ZeroAddressAndGetRelativeValueUnified() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        priceOracleAggregator.getRelativeValueUnified(address(0), address(token1), 1e18);

        vm.expectRevert(Errors.ZeroAddress.selector);
        priceOracleAggregator.getRelativeValueUnified(address(token0), address(0), 1e18);
    }

    function test_RevertIf_PriceOracleNotFoundT1AndGetRelativeValueUnified() public {
        vm.expectRevert(abi.encodeWithSelector(IPriceOracleAggregator.PriceOracleNotFound.selector, address(token0)));
        priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token0), address(mockPriceOracle));

        vm.expectRevert(abi.encodeWithSelector(IPriceOracleAggregator.PriceOracleNotFound.selector, address(token1)));
        priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);
    }

    function test_RevertIf_PriceOracleNotFoundT0AndGetRelativeValueUnified() public {
        vm.expectRevert(abi.encodeWithSelector(IPriceOracleAggregator.PriceOracleNotFound.selector, address(token0)));
        priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);

        vm.prank(roles.oracleManager);
        priceOracleAggregator.setPriceOracle(address(token1), address(mockPriceOracle));

        vm.expectRevert(abi.encodeWithSelector(IPriceOracleAggregator.PriceOracleNotFound.selector, address(token0)));
        priceOracleAggregator.getRelativeValueUnified(address(token0), address(token1), 1e18);
    }
}
