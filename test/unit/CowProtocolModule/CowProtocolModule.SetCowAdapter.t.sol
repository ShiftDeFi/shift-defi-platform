// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";

contract CowProtocolModuleSetCowAdapterTest is Test {
    MockCowProtocolModule internal module;
    MockCowProtocolAdapter internal adapter;
    MockCowProtocolAdapter internal newAdapter;

    function setUp() public {
        module = new MockCowProtocolModule();
        adapter = new MockCowProtocolAdapter(address(module));
        newAdapter = new MockCowProtocolAdapter(address(module));
    }

    function test_SetCowAdapter() public {
        vm.expectEmit(true, true, false, false, address(module));
        emit ICowProtocolModule.CowAdapterUpdated(address(0), address(adapter));

        module.setCowAdapter(address(adapter));

        assertEq(module.cowAdapter(), address(adapter));
    }

    function test_SetCowAdapter_ReplacesIdleAdapter() public {
        module.setCowAdapter(address(adapter));

        vm.expectEmit(true, true, false, false, address(module));
        emit ICowProtocolModule.CowAdapterUpdated(address(adapter), address(newAdapter));

        module.setCowAdapter(address(newAdapter));

        assertEq(module.cowAdapter(), address(newAdapter));
    }

    function test_RevertIf_SetCowAdapter_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        module.setCowAdapter(address(0));
    }

    function test_RevertIf_SetCowAdapter_AdapterOwnedByAnother() public {
        MockCowProtocolAdapter foreignAdapter = new MockCowProtocolAdapter(makeAddr("OTHER_OWNER"));

        vm.expectRevert(
            abi.encodeWithSelector(ICowProtocolModule.CowAdapterNotOwned.selector, address(foreignAdapter))
        );
        module.setCowAdapter(address(foreignAdapter));

        assertEq(module.cowAdapter(), address(0));
    }

    function test_RevertIf_SetCowAdapter_AdapterHasNoCode() public {
        vm.expectRevert();
        module.setCowAdapter(makeAddr("NOT_A_CONTRACT"));

        assertEq(module.cowAdapter(), address(0));
    }

    function test_RevertIf_SetCowAdapter_PendingOrdersOnOutgoingAdapter() public {
        module.setCowAdapter(address(adapter));
        adapter.setPendingOrderCount(3);

        vm.expectRevert(abi.encodeWithSelector(Errors.PendingCowOrders.selector, address(module), 3));
        module.setCowAdapter(address(newAdapter));

        assertEq(module.cowAdapter(), address(adapter));
    }
}
