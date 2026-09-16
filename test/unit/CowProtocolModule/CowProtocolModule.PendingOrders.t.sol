// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {Test} from "forge-std/Test.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";

contract CowProtocolModulePendingOrdersTest is Test {
    MockCowProtocolModule internal module;
    MockCowProtocolAdapter internal adapter;

    function setUp() public {
        module = new MockCowProtocolModule();
        adapter = new MockCowProtocolAdapter(address(module));
    }

    function test_PendingCowOrderCount_ZeroWhenAdapterUnset() public view {
        assertEq(module.cowAdapter(), address(0));
        assertEq(module.pendingCowOrderCount(), 0);
    }

    function testFuzz_PendingCowOrderCount(uint256 pendingOrders) public {
        module.setCowAdapter(address(adapter));
        adapter.setPendingOrderCount(pendingOrders);

        assertEq(module.pendingCowOrderCount(), pendingOrders);
    }

    function test_RequireNoPendingOrders_NoOpWhenAdapterUnset() public {
        module.requireNoPendingOrders();

        assertEq(module.cowAdapter(), address(0));
    }

    function test_RequireNoPendingOrders() public {
        module.setCowAdapter(address(adapter));

        vm.expectCall(address(adapter), abi.encodeCall(ICowProtocolAdapter.requireNoPendingOrders, ()));
        module.requireNoPendingOrders();
    }

    function test_RevertIf_RequireNoPendingOrders_OrdersStillPending() public {
        module.setCowAdapter(address(adapter));
        adapter.setPendingOrderCount(2);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 2));
        module.requireNoPendingOrders();
    }
}
