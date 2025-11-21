// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library RingCacheLibrary {
    uint256 internal constant DEFAULT_CACHE_SIZE = 10;
    uint256 internal constant MAX_CACHE_SIZE = 256;

    struct RingCache {
        mapping(bytes32 => uint256) indices;
        mapping(uint256 => bytes32) ring;
        uint256 head;
        uint256 size;
        uint256 maxCacheSize;
        bytes32 id;
    }

    event CacheStored(bytes32 id, bytes32 value);
    event CacheEvicted(bytes32 id, bytes32 value);

    error AlreadyInitialized(bytes32 id);
    error AlreadyExists(bytes32 id, bytes32 data);
    error InvalidSize(uint256 proposedSize, uint256 maximumSize);
    error DoesNotExists(bytes32 id, bytes32 data);

    function initialize(RingCache storage _cache, bytes32 _id, uint256 _cacheSize) internal {
        require(_cache.maxCacheSize == 0, AlreadyInitialized(_cache.id));
        require(_cacheSize > 0, InvalidSize(_cacheSize, MAX_CACHE_SIZE));
        require(_cacheSize < MAX_CACHE_SIZE, InvalidSize(_cacheSize, MAX_CACHE_SIZE));
        _cache.maxCacheSize = _cacheSize;
        _cache.id = _id;
    }

    function add(RingCache storage _cache, bytes32 value) internal {
        if (exists(_cache, value)) return;
        uint256 index = (_cache.head++) % _cache.maxCacheSize;
        bytes32 oldValue = _cache.ring[index];
        if (_cache.indices[oldValue] == index + 1) delete _cache.indices[oldValue];
        else _cache.size++;
        _cache.indices[value] = index + 1;
        _cache.ring[index] = value;
    }

    function remove(RingCache storage _cache, bytes32 value) internal {
        uint256 index = _cache.indices[value];
        require(index != 0, DoesNotExists(_cache.id, value));
        index = index - 1;
        require(_cache.ring[index] == value, DoesNotExists(_cache.id, value));
        delete _cache.indices[value];
        delete _cache.ring[index];
        _cache.size--;
    }
    function exists(RingCache storage _cache, bytes32 value) internal view returns (bool) {
        return _cache.indices[value] != 0;
    }

    function all(RingCache storage _cache) internal view returns (bytes32[] memory out) {
        out = new bytes32[](_cache.size);
        for (uint256 i = 0; i < _cache.size; ) {
            uint256 index = (_cache.head + i) % _cache.maxCacheSize;
            if (_cache.ring[index] != bytes32(0)) {
                out[i] = _cache.ring[index];
            }
            unchecked {
                ++i;
            }
        }
    }

    function currentSize(RingCache storage _cache) internal view returns (uint256) {
        return _cache.size;
    }
}
