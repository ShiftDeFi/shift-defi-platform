// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {RingCacheLibrary} from "contracts/libraries/RingCacheLibrary.sol";

contract RingCacheLibraryTest is Test {
    RingCacheLibrary.RingCache ringCache;

    function test_Initialize() public {
        bytes32 id = "test_id";
        uint256 cacheSize = 10;

        RingCacheLibrary.initialize(ringCache, id, cacheSize);

        assertEq(ringCache.id, id, "test_Initialize: id mismatch");
        assertEq(ringCache.maxCacheSize, cacheSize, "test_Initialize: maxCacheSize mismatch");
        assertEq(ringCache.size, 0, "test_Initialize: size mismatch");
        assertEq(ringCache.head, 0, "test_Initialize: head mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_AlreadyInitialized() public {
        bytes32 id = "test_id";
        uint256 cacheSize = 10;

        RingCacheLibrary.initialize(ringCache, id, cacheSize);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLibrary.AlreadyInitialized.selector, id));
        RingCacheLibrary.initialize(ringCache, id, cacheSize);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_InvalidCacheSize_TooSmall() public {
        vm.expectRevert(
            abi.encodeWithSelector(RingCacheLibrary.InvalidSize.selector, 0, RingCacheLibrary.MAX_CACHE_SIZE)
        );
        RingCacheLibrary.initialize(ringCache, "test_id", 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_InvalidCacheSize_TooLarge() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                RingCacheLibrary.InvalidSize.selector,
                RingCacheLibrary.MAX_CACHE_SIZE,
                RingCacheLibrary.MAX_CACHE_SIZE
            )
        );
        RingCacheLibrary.initialize(ringCache, "test_id", RingCacheLibrary.MAX_CACHE_SIZE);
    }

    function testFuzz_Add(uint256 cacheSize) public {
        cacheSize = bound(cacheSize, 1, RingCacheLibrary.MAX_CACHE_SIZE - 1);

        RingCacheLibrary.initialize(ringCache, "test_id", cacheSize);

        for (uint256 i = 0; i < cacheSize; i++) {
            assertEq(ringCache.size, i, "testFuzz_Add: size mismatch before add");
            assertEq(ringCache.head, i, "testFuzz_Add: head mismatch before add");

            bytes32 value = bytes32(i + 1);
            RingCacheLibrary.add(ringCache, value);

            assertEq(ringCache.size, i + 1, "testFuzz_Add: size mismatch after add");
            assertEq(ringCache.head, i + 1, "testFuzz_Add: head mismatch after add");
            assertEq(ringCache.ring[i], value, "testFuzz_Add: ring value mismatch");
            assertEq(ringCache.indices[value], i + 1, "testFuzz_Add: indices mismatch");
        }
    }
}
