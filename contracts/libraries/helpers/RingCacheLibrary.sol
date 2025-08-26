// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library RingCacheLibrary {
    uint256 internal constant DEFAULT_CACHE_SIZE = 10;

    struct RingCache {
        mapping(bytes32 => uint256) indices;
        mapping(uint256 => bytes32) ring;
        uint256 head;
        uint256 size;
        uint256 maxCacheSize;
    }

    event CacheStored(bytes32 value);
    event CacheEvicted(bytes32 value);

    error AlreadyInitialized();
    error AlreadyExists(bytes32);
    error InvalidSize();
    error DoesNotExists(bytes32);

    function initialize(RingCache storage _cache, uint256 _cacheSize) internal {
        require(_cache.maxCacheSize == 0, AlreadyInitialized());
        require(_cacheSize > 0, InvalidSize());
        _cache.maxCacheSize = _cacheSize;
    }

    function add(RingCache storage _cache, bytes32 value) internal {
        if (exists(_cache, value)) return;
        if (_cache.size < _cache.maxCacheSize) {
            uint256 index = (_cache.head + _cache.size) % _cache.maxCacheSize;
            _cache.indices[value] = index + 1;
            _cache.ring[index] = value;
            _cache.size++;
        } else {
            bytes32 old = _cache.ring[_cache.head];
            delete _cache.indices[old];
            _cache.ring[_cache.head] = value;
            _cache.indices[value] = _cache.head + 1;
            _cache.head = (_cache.head + 1) % _cache.maxCacheSize;
        }
    }

    function remove(RingCache storage _cache, bytes32 value) internal {
        uint256 index = _cache.indices[value];
        require(index != 0, DoesNotExists(value));
        index = index - 1;
        if (_cache.ring[index] == value) {
            delete _cache.indices[value];
            delete _cache.ring[index];
            _cache.size--;
        }
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
