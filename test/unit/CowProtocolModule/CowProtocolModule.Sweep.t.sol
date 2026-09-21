// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {Test} from "forge-std/Test.sol";

import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract CowProtocolModuleSweepTest is Test {
    MockCowProtocolModule internal module;
    MockCowProtocolAdapter internal adapter;
    MockERC20 internal token;

    uint256 internal constant DONATION = 7e18;

    function setUp() public {
        module = new MockCowProtocolModule();
        adapter = new MockCowProtocolAdapter(address(module));
        token = new MockERC20("Token", "TKN", 18);

        module.setCowAdapter(address(adapter));
        adapter.setOwner(address(module));
        adapter.setDeployedLaneCount(1);
    }

    function test_SweepCowAdapter() public {
        token.mint(address(adapter), DONATION);

        module.sweepCowAdapter(address(token));

        assertEq(token.balanceOf(address(module)), DONATION);
        assertEq(token.balanceOf(address(adapter)), 0);
    }

    function test_SweepCowLane() public {
        token.mint(address(adapter), DONATION);

        module.sweepCowLane(0, address(token));

        assertEq(token.balanceOf(address(module)), DONATION);
    }

    function test_RevertIf_SweepCowAdapter_NothingToSweep() public {
        vm.expectRevert(ICowProtocolAdapter.NothingToSweep.selector);
        module.sweepCowAdapter(address(token));
    }

    function test_RevertIf_SweepCowLane_LaneIndexOutOfRange() public {
        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.LaneIndexOutOfRange.selector, 1, 1));
        module.sweepCowLane(1, address(token));
    }

    function test_RevertIf_SweepCowAdapter_AdapterNotSet() public {
        MockCowProtocolModule bare = new MockCowProtocolModule();

        vm.expectRevert(ICowProtocolModule.CowAdapterNotSet.selector);
        bare.sweepCowAdapter(address(token));
    }

    function test_RevertIf_SweepCowLane_AdapterNotSet() public {
        MockCowProtocolModule bare = new MockCowProtocolModule();

        vm.expectRevert(ICowProtocolModule.CowAdapterNotSet.selector);
        bare.sweepCowLane(0, address(token));
    }
}
