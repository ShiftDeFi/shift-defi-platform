// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {RingCacheLib} from "contracts/libraries/RingCacheLib.sol";

contract RingCacheLibTest is Test {
    RingCacheLib.RingCache ringCache;

    uint256 internal constant DEFAULT_CACHE_SIZE = 4;
    uint256 internal constant CACHE_SIZE_TWO = 2;
    uint256 internal constant CACHE_SIZE_ONE = 1;
    uint256 internal constant INIT_CACHE_SIZE = 10;
    bytes32 internal constant TEST_ID = bytes32("test_id");
    uint256 internal constant STRESS_ADD_COUNT = 1000;
    uint256 internal constant INVARIANT_ADD_COUNT = 20;

    function test_Initialize() public {
        uint256 cacheSize = INIT_CACHE_SIZE;
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        assertEq(ringCache.id, TEST_ID, "test_Initialize: id mismatch");
        assertEq(ringCache.maxCacheSize, cacheSize, "test_Initialize: maxCacheSize mismatch");
        assertEq(ringCache.head, 0, "test_Initialize: head mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_AlreadyInitialized() public {
        RingCacheLib.initialize(ringCache, TEST_ID, INIT_CACHE_SIZE);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.AlreadyInitialized.selector, TEST_ID));
        RingCacheLib.initialize(ringCache, TEST_ID, INIT_CACHE_SIZE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_InvalidCacheSize_TooSmall() public {
        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.InvalidSize.selector, 0, RingCacheLib.MAX_CACHE_SIZE));
        RingCacheLib.initialize(ringCache, TEST_ID, 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_InvalidCacheSize_TooLarge() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                RingCacheLib.InvalidSize.selector,
                RingCacheLib.MAX_CACHE_SIZE,
                RingCacheLib.MAX_CACHE_SIZE
            )
        );
        RingCacheLib.initialize(ringCache, TEST_ID, RingCacheLib.MAX_CACHE_SIZE);
    }

    function test_Initialize_BoundarySize() public {
        uint256 cacheSize = RingCacheLib.MAX_CACHE_SIZE - 1;
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);
        assertEq(ringCache.maxCacheSize, cacheSize, "test_Initialize_BoundarySize: maxCacheSize mismatch");
    }

    function test_Add_SingleElement() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));

        RingCacheLib.add(ringCache, v);

        assertEq(ringCache.head, 1, "test_Add_SingleElement: head mismatch");
        assertEq(ringCache.ring[1], v, "test_Add_SingleElement: ring value mismatch");
        assertEq(ringCache.indices[v], 1, "test_Add_SingleElement: indices mismatch");
        assertTrue(RingCacheLib.exists(ringCache, v), "test_Add_SingleElement: exists mismatch");
    }

    function test_Add_UntilFull() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);

        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            bytes32 v = bytes32(uint256(i + 100));
            RingCacheLib.add(ringCache, v);
            assertEq(ringCache.head, i + 1, "test_Add_UntilFull: head mismatch");
            assertEq(ringCache.ring[i + 1], v, "test_Add_UntilFull: ring value mismatch");
            assertEq(ringCache.indices[v], i + 1, "test_Add_UntilFull: indices mismatch");
            assertTrue(RingCacheLib.exists(ringCache, v), "test_Add_UntilFull: exists mismatch");
        }
    }

    function test_Add_OverwriteOnFull() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            RingCacheLib.add(ringCache, bytes32(uint256(i + 100)));
        }

        assertEq(ringCache.head, DEFAULT_CACHE_SIZE, "test_Add_OverwriteOnFull: head before overwrite mismatch");

        RingCacheLib.add(ringCache, bytes32(uint256(999)));
        assertEq(ringCache.head, DEFAULT_CACHE_SIZE + 1, "test_Add_OverwriteOnFull: head after overwrite mismatch");
        assertEq(ringCache.ring[1], bytes32(uint256(999)), "test_Add_OverwriteOnFull: overwritten slot mismatch");
    }

    function test_Add_OverwriteClearsOldIndices() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_TWO);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        bytes32 v3 = bytes32(uint256(3));

        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);

        assertFalse(
            RingCacheLib.exists(ringCache, v1),
            "test_Add_OverwriteClearsOldIndices: evicted value must not exist"
        );
        assertTrue(RingCacheLib.exists(ringCache, v2), "test_Add_OverwriteClearsOldIndices: v2 must exist");
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_Add_OverwriteClearsOldIndices: v3 must exist");
    }

    function testFuzz_Add_RandomSizeAndValues(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        bytes32[] memory values = new bytes32[](cacheSize);
        for (uint256 i = 0; i < cacheSize; i++) {
            values[i] = bytes32(vm.randomUint());
        }

        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        for (uint256 i = 0; i < cacheSize; i++) {
            RingCacheLib.add(ringCache, values[i]);
            assertEq(ringCache.head, i + 1, "testFuzz_Add_RandomSizeAndValues: head mismatch");
            assertEq(ringCache.ring[i + 1], values[i], "testFuzz_Add_RandomSizeAndValues: ring value mismatch");
            assertEq(ringCache.indices[values[i]], i + 1, "testFuzz_Add_RandomSizeAndValues: indices mismatch");
        }

        bytes32[] memory evictingValues = new bytes32[](cacheSize);
        for (uint256 i = 0; i < cacheSize; i++) {
            evictingValues[i] = bytes32(vm.randomUint());
        }

        for (uint256 i = 0; i < cacheSize; i++) {
            uint256 index = (ringCache.head % ringCache.maxCacheSize) + 1;
            RingCacheLib.add(ringCache, evictingValues[i]);
            assertEq(
                ringCache.ring[index],
                evictingValues[i],
                "testFuzz_Add_RandomSizeAndValues: ring after evict mismatch"
            );
            assertEq(
                ringCache.indices[evictingValues[i]],
                index,
                "testFuzz_Add_RandomSizeAndValues: indices after evict mismatch"
            );
        }
    }

    function test_Remove_SingleElement() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));
        RingCacheLib.add(ringCache, v);

        RingCacheLib.remove(ringCache, v);
        assertFalse(RingCacheLib.exists(ringCache, v), "test_Remove_SingleElement: exists after remove mismatch");
        assertEq(ringCache.indices[v], 0, "test_Remove_SingleElement: indices after remove mismatch");
        assertEq(ringCache.ring[1], bytes32(0), "test_Remove_SingleElement: ring after remove mismatch");
    }

    function test_Remove_FirstElement() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);

        RingCacheLib.remove(ringCache, v1);
        assertFalse(RingCacheLib.exists(ringCache, v1), "test_Remove_FirstElement: v1 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v2), "test_Remove_FirstElement: v2 must exist");
    }

    function test_Remove_LastElement() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);

        RingCacheLib.remove(ringCache, v2);
        assertTrue(RingCacheLib.exists(ringCache, v1), "test_Remove_LastElement: v1 must exist");
        assertFalse(RingCacheLib.exists(ringCache, v2), "test_Remove_LastElement: v2 must not exist");
    }

    function test_Remove_MiddleElement() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        bytes32 v3 = bytes32(uint256(103));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);

        RingCacheLib.remove(ringCache, v2);
        assertTrue(RingCacheLib.exists(ringCache, v1), "test_Remove_MiddleElement: v1 must exist");
        assertFalse(RingCacheLib.exists(ringCache, v2), "test_Remove_MiddleElement: v2 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_Remove_MiddleElement: v3 must exist");
    }

    function test_Remove_AllElements_NotFull() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32[] memory values = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            values[i] = bytes32(uint256(i + 100));
            RingCacheLib.add(ringCache, values[i]);
        }

        for (uint256 i = 0; i < 3; i++) {
            RingCacheLib.remove(ringCache, values[i]);
        }

        assertEq(ringCache.head, 3, "test_Remove_AllElements_NotFull: head mismatch");

        bytes32[] memory all = RingCacheLib.all(ringCache);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(all[i], bytes32(0), "test_Remove_AllElements_NotFull: all slot must be empty");
        }
    }

    function test_Remove_AllElements_Full() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32[] memory values = new bytes32[](DEFAULT_CACHE_SIZE);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            values[i] = bytes32(uint256(i + 100));
            RingCacheLib.add(ringCache, values[i]);
        }

        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            RingCacheLib.remove(ringCache, values[i]);
        }

        assertEq(ringCache.head, DEFAULT_CACHE_SIZE, "test_Remove_AllElements_Full: head mismatch");

        bytes32[] memory all = RingCacheLib.all(ringCache);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            assertEq(all[i], bytes32(0), "test_Remove_AllElements_Full: all slot must be empty");
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Remove_NonExistentValue() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.DoesNotExists.selector, TEST_ID, bytes32(uint256(999))));
        RingCacheLib.remove(ringCache, bytes32(uint256(999)));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Remove_AlreadyRemovedValue() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));
        RingCacheLib.add(ringCache, v);
        RingCacheLib.remove(ringCache, v);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.DoesNotExists.selector, TEST_ID, v));
        RingCacheLib.remove(ringCache, v);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Remove_AfterOverwrite_OldValue() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_TWO);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        bytes32 v3 = bytes32(uint256(3));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.DoesNotExists.selector, TEST_ID, v1));
        RingCacheLib.remove(ringCache, v1);
    }

    function test_Exists_AfterAdd() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));
        RingCacheLib.add(ringCache, v);
        assertTrue(RingCacheLib.exists(ringCache, v), "test_Exists_AfterAdd: exists mismatch");
    }

    function test_Exists_AfterRemove() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));
        RingCacheLib.add(ringCache, v);
        RingCacheLib.remove(ringCache, v);
        assertFalse(RingCacheLib.exists(ringCache, v), "test_Exists_AfterRemove: exists after remove mismatch");
    }

    function test_Exists_AfterOverwrite() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_TWO);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        bytes32 v3 = bytes32(uint256(3));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);
        assertFalse(RingCacheLib.exists(ringCache, v1), "test_Exists_AfterOverwrite: evicted v1 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_Exists_AfterOverwrite: v3 must exist");
    }

    function test_All_EmptyCache() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32[] memory all = RingCacheLib.all(ringCache);
        assertEq(all.length, DEFAULT_CACHE_SIZE, "test_All_EmptyCache: length mismatch");
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            assertEq(all[i], bytes32(0), "test_All_EmptyCache: slot must be empty");
        }
    }

    function test_All_PartialCache() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);

        bytes32[] memory all = RingCacheLib.all(ringCache);
        assertEq(all.length, DEFAULT_CACHE_SIZE, "test_All_PartialCache: length mismatch");
        assertEq(all[0], v1, "test_All_PartialCache: slot 0 mismatch");
        assertEq(all[1], v2, "test_All_PartialCache: slot 1 mismatch");
        assertEq(all[2], bytes32(0), "test_All_PartialCache: slot 2 must be empty");
        assertEq(all[3], bytes32(0), "test_All_PartialCache: slot 3 must be empty");
    }

    function test_All_FullCache() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32[] memory values = new bytes32[](DEFAULT_CACHE_SIZE);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            values[i] = bytes32(uint256(i + 100));
            RingCacheLib.add(ringCache, values[i]);
        }

        bytes32[] memory all = RingCacheLib.all(ringCache);
        assertEq(all.length, DEFAULT_CACHE_SIZE, "test_All_FullCache: length mismatch");
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            assertEq(all[i], values[i], "test_All_FullCache: slot value mismatch");
        }
    }

    function test_All_AfterOverwrite() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            RingCacheLib.add(ringCache, bytes32(uint256(i + 100)));
        }
        RingCacheLib.add(ringCache, bytes32(uint256(999)));

        bytes32[] memory all = RingCacheLib.all(ringCache);
        assertEq(all[0], bytes32(uint256(999)), "test_All_AfterOverwrite: slot 0 mismatch");
        assertEq(all[1], bytes32(uint256(101)), "test_All_AfterOverwrite: slot 1 mismatch");
        assertEq(all[2], bytes32(uint256(102)), "test_All_AfterOverwrite: slot 2 mismatch");
        assertEq(all[3], bytes32(uint256(103)), "test_All_AfterOverwrite: slot 3 mismatch");
    }

    function test_All_AfterPartialRemove() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        bytes32 v3 = bytes32(uint256(103));
        bytes32 v4 = bytes32(uint256(104));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);
        RingCacheLib.add(ringCache, v4);
        RingCacheLib.remove(ringCache, v2);
        RingCacheLib.remove(ringCache, v4);

        bytes32[] memory all = RingCacheLib.all(ringCache);
        assertEq(all[0], v1, "test_All_AfterPartialRemove: slot 0 mismatch");
        assertEq(all[1], bytes32(0), "test_All_AfterPartialRemove: slot 1 must be empty");
        assertEq(all[2], v3, "test_All_AfterPartialRemove: slot 2 mismatch");
        assertEq(all[3], bytes32(0), "test_All_AfterPartialRemove: slot 3 must be empty");
    }

    function test_Retry_FullCycle_AddGetRemove() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32[] memory values = new bytes32[](DEFAULT_CACHE_SIZE);
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            values[i] = bytes32(uint256(i + 1000));
            RingCacheLib.add(ringCache, values[i]);
        }
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            assertTrue(RingCacheLib.exists(ringCache, values[i]), "test_Retry_FullCycle_AddGetRemove: exists mismatch");
        }
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            RingCacheLib.remove(ringCache, values[i]);
        }
        for (uint256 i = 0; i < DEFAULT_CACHE_SIZE; i++) {
            assertFalse(
                RingCacheLib.exists(ringCache, values[i]),
                "test_Retry_FullCycle_AddGetRemove: exists after remove mismatch"
            );
        }
    }

    function test_Retry_EvictionClearsOldEntry() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_TWO);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        bytes32 v3 = bytes32(uint256(3));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);

        assertFalse(RingCacheLib.exists(ringCache, v1), "test_Retry_EvictionClearsOldEntry: evicted v1 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v2), "test_Retry_EvictionClearsOldEntry: v2 must exist");
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_Retry_EvictionClearsOldEntry: v3 must exist");
    }

    function test_Retry_PartialRemoveThenRefill() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(101));
        bytes32 v2 = bytes32(uint256(102));
        bytes32 v3 = bytes32(uint256(103));
        bytes32 v4 = bytes32(uint256(104));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.add(ringCache, v3);
        RingCacheLib.add(ringCache, v4);
        RingCacheLib.remove(ringCache, v2);
        RingCacheLib.remove(ringCache, v4);

        bytes32 v5 = bytes32(uint256(105));
        bytes32 v6 = bytes32(uint256(106));
        RingCacheLib.add(ringCache, v5);
        RingCacheLib.add(ringCache, v6);

        assertFalse(
            RingCacheLib.exists(ringCache, v1),
            "test_Retry_PartialRemoveThenRefill: v1 overwritten must not exist"
        );
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_Retry_PartialRemoveThenRefill: v3 must exist");
        assertTrue(RingCacheLib.exists(ringCache, v5), "test_Retry_PartialRemoveThenRefill: v5 must exist");
        assertTrue(RingCacheLib.exists(ringCache, v6), "test_Retry_PartialRemoveThenRefill: v6 must exist");
    }

    function test_Retry_SlotReuseAfterOverwrite() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_TWO);
        RingCacheLib.add(ringCache, bytes32(uint256(1)));
        RingCacheLib.add(ringCache, bytes32(uint256(2)));
        RingCacheLib.add(ringCache, bytes32(uint256(3)));
        RingCacheLib.add(ringCache, bytes32(uint256(4)));

        assertEq(ringCache.ring[1], bytes32(uint256(3)), "test_Retry_SlotReuseAfterOverwrite: ring slot 1 mismatch");
        assertEq(ringCache.ring[2], bytes32(uint256(4)), "test_Retry_SlotReuseAfterOverwrite: ring slot 2 mismatch");
    }

    function test_Retry_HeadNeverDecreases() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        uint256 prevHead = 0;
        for (uint256 i = 0; i < 10; i++) {
            RingCacheLib.add(ringCache, bytes32(uint256(i + 100)));
            assertGe(ringCache.head, prevHead, "test_Retry_HeadNeverDecreases: head must not decrease");
            prevHead = ringCache.head;
        }
        RingCacheLib.remove(ringCache, bytes32(uint256(109)));
        assertGe(ringCache.head, prevHead, "test_Retry_HeadNeverDecreases: head after remove must not decrease");
    }

    function testFuzz_Invariant_SizeNeverExceedsMax(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        for (uint256 i = 0; i < cacheSize * 2; i++) {
            RingCacheLib.add(ringCache, bytes32(vm.randomUint()));
        }
    }

    function testFuzz_Invariant_HeadMonotonicallyInc(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);
        uint256 prevHead = 0;

        for (uint256 i = 0; i < INVARIANT_ADD_COUNT; i++) {
            RingCacheLib.add(ringCache, bytes32(vm.randomUint()));
            assertGt(ringCache.head, prevHead, "testFuzz_Invariant_HeadMonotonicallyInc: head must increase");
            prevHead = ringCache.head;
        }
    }

    function testFuzz_Invariant_IndexAlwaysInBounds(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        for (uint256 i = 0; i < cacheSize + 2; i++) {
            RingCacheLib.add(ringCache, bytes32(vm.randomUint()));
        }
        for (uint256 i = 1; i <= cacheSize; i++) {
            bytes32 v = ringCache.ring[i];
            if (v != bytes32(0)) {
                assertGe(ringCache.indices[v], 1, "testFuzz_Invariant_IndexAlwaysInBounds: index must be >= 1");
                assertLe(
                    ringCache.indices[v],
                    cacheSize,
                    "testFuzz_Invariant_IndexAlwaysInBounds: index must be <= maxCacheSize"
                );
            }
        }
    }

    function testFuzz_Invariant_IndicesConsistency(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        for (uint256 i = 0; i < cacheSize * 2; i++) {
            bytes32 v = bytes32(vm.randomUint());
            RingCacheLib.add(ringCache, v);
        }
        for (uint256 i = 1; i <= cacheSize; i++) {
            bytes32 v = ringCache.ring[i];
            if (v != bytes32(0)) {
                assertEq(
                    ringCache.ring[ringCache.indices[v]],
                    v,
                    "testFuzz_Invariant_IndicesConsistency: indices consistency mismatch"
                );
            }
        }
    }

    function testFuzz_Invariant_SlotZeroAlwaysEmpty(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, RingCacheLib.MAX_CACHE_SIZE - 1);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);
        for (uint256 i = 0; i < cacheSize * 3; i++) {
            RingCacheLib.add(ringCache, bytes32(vm.randomUint()));
        }
        assertEq(ringCache.ring[0], bytes32(0), "testFuzz_Invariant_SlotZeroAlwaysEmpty: slot 0 must be empty");
    }

    function test_EdgeCase_MaxCacheSize_One() public {
        RingCacheLib.initialize(ringCache, TEST_ID, CACHE_SIZE_ONE);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);

        assertFalse(RingCacheLib.exists(ringCache, v1), "test_EdgeCase_MaxCacheSize_One: evicted v1 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v2), "test_EdgeCase_MaxCacheSize_One: v2 must exist");
        assertEq(ringCache.ring[1], v2, "test_EdgeCase_MaxCacheSize_One: ring slot 1 mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_EdgeCase_ZeroValue() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.NullValue.selector, TEST_ID));
        RingCacheLib.add(ringCache, bytes32(0));
    }

    function test_EdgeCase_MaxUint256Value() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(type(uint256).max);
        RingCacheLib.add(ringCache, v);
        assertTrue(RingCacheLib.exists(ringCache, v), "test_EdgeCase_MaxUint256Value: exists mismatch");
        assertEq(ringCache.ring[1], v, "test_EdgeCase_MaxUint256Value: ring value mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_EdgeCase_DuplicateAdd() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v = bytes32(uint256(111));
        RingCacheLib.add(ringCache, v);
        vm.expectRevert(abi.encodeWithSelector(RingCacheLib.ValueAlreadyExists.selector, TEST_ID, v));
        RingCacheLib.add(ringCache, v);
    }

    function testFuzz_StressTest_ManyAdds(uint256 randomSeed) public {
        uint256 cacheSize = bound(randomSeed, 1, 50);
        RingCacheLib.initialize(ringCache, TEST_ID, cacheSize);

        for (uint256 i = 0; i < STRESS_ADD_COUNT; i++) {
            RingCacheLib.add(ringCache, bytes32(vm.randomUint()));
        }
        assertEq(ringCache.head, STRESS_ADD_COUNT, "testFuzz_StressTest_ManyAdds: head mismatch");
    }

    function test_EdgeCase_AlternatingAddRemove() public {
        RingCacheLib.initialize(ringCache, TEST_ID, DEFAULT_CACHE_SIZE);
        bytes32 v1 = bytes32(uint256(1));
        bytes32 v2 = bytes32(uint256(2));
        bytes32 v3 = bytes32(uint256(3));

        RingCacheLib.add(ringCache, v1);
        RingCacheLib.add(ringCache, v2);
        RingCacheLib.remove(ringCache, v1);
        RingCacheLib.add(ringCache, v3);
        RingCacheLib.remove(ringCache, v2);
        RingCacheLib.add(ringCache, v1);

        assertFalse(RingCacheLib.exists(ringCache, v2), "test_EdgeCase_AlternatingAddRemove: v2 must not exist");
        assertTrue(RingCacheLib.exists(ringCache, v1), "test_EdgeCase_AlternatingAddRemove: v1 must exist");
        assertTrue(RingCacheLib.exists(ringCache, v3), "test_EdgeCase_AlternatingAddRemove: v3 must exist");
    }
}
