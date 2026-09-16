// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";

contract CowProtocolModuleStorageTest is Test {
    MockCowProtocolModule internal module;

    string internal constant NAMESPACE_ID = "shift-defi.storage.CowProtocolModule";

    function setUp() public {
        module = new MockCowProtocolModule();
    }

    function testFuzz_StorageLocationFollowsErc7201(address cowAdapter) public {
        bytes32 slot = keccak256(abi.encode(uint256(keccak256(bytes(NAMESPACE_ID))) - 1)) & ~bytes32(uint256(0xff));

        module.setCowAdapterRaw(cowAdapter);

        assertEq(vm.load(address(module), slot), bytes32(uint256(uint160(cowAdapter))));
    }

    function test_StorageLocationOccupiesNoSequentialSlot() public {
        module.setCowAdapterRaw(address(this));

        for (uint256 i = 0; i < 64; ++i) {
            assertEq(vm.load(address(module), bytes32(i)), bytes32(0));
        }
    }
}
