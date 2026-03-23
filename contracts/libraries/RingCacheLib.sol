// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title RingCacheLib
/// @notice Minimal ring-buffer cache with O(1) add/remove/exists.
library RingCacheLib {
    uint256 internal constant MAX_CACHE_SIZE = 256;

    struct RingCache {
        mapping(bytes32 => uint256) indices;
        mapping(uint256 => bytes32) ring;
        uint256 head;
        uint256 maxCacheSize;
        bytes32 id;
    }

    event Evicted(bytes32 id, bytes32 value);
    event Stored(bytes32 id, bytes32 value);
    event Removed(bytes32 id, bytes32 value);

    error AlreadyInitialized(bytes32 id);
    error InvalidSize(uint256 proposedSize, uint256 maximumSize);
    error DoesNotExists(bytes32 id, bytes32 data);
    error NullValue(bytes32 id);
    error ValueAlreadyExists(bytes32 id, bytes32 value);
    error ValueMismatch(bytes32 id, bytes32 value, bytes32 storedValue);

    /**
     * @notice Initializes the ring cache with an id and max size.
     * @dev Reverts if called twice or if size is zero/too large.
     * @param _cache Storage cache struct.
     * @param _id Identifier used in errors/events.
     * @param _cacheSize Maximum number of cached items (must be >0 and < MAX_CACHE_SIZE).
     */
    function initialize(RingCache storage _cache, bytes32 _id, uint256 _cacheSize) internal {
        require(_cache.maxCacheSize == 0, AlreadyInitialized(_cache.id));
        require(_cacheSize > 0, InvalidSize(_cacheSize, MAX_CACHE_SIZE));
        require(_cacheSize < MAX_CACHE_SIZE, InvalidSize(_cacheSize, MAX_CACHE_SIZE));
        _cache.maxCacheSize = _cacheSize;
        _cache.id = _id;
    }

    /**
     * @notice Adds a value to the cache; evicts old entry if buffer is full.
     * @dev No-op if value already exists.
     * @param _cache Storage cache struct.
     * @param value Value to cache.
     */
    function add(RingCache storage _cache, bytes32 value) internal {
        require(value != bytes32(0), NullValue(_cache.id));
        require(!exists(_cache, value), ValueAlreadyExists(_cache.id, value));

        uint256 index = (_cache.head++ % _cache.maxCacheSize) + 1;
        bytes32 oldValue = _cache.ring[index];
        if (oldValue != bytes32(0)) {
            delete _cache.indices[oldValue];
            emit Evicted(_cache.id, oldValue);
        }
        _cache.indices[value] = index;
        _cache.ring[index] = value;

        emit Stored(_cache.id, value);
    }

    /**
     * @notice Removes a value from the cache.
     * @dev Reverts if value not present.
     * @param _cache Storage cache struct.
     * @param value Value to remove.
     */
    function remove(RingCache storage _cache, bytes32 value) internal {
        require(exists(_cache, value), DoesNotExists(_cache.id, value));
        uint256 index = _cache.indices[value];
        bytes32 storedValue = _cache.ring[index];
        require(storedValue == value, ValueMismatch(_cache.id, value, storedValue));
        delete _cache.indices[value];
        delete _cache.ring[index];
        emit Removed(_cache.id, value);
    }

    /**
     * @notice Checks whether a value exists in the cache.
     * @param _cache Storage cache struct.
     * @param value Value to check.
     * @return True if present, false otherwise.
     */
    function exists(RingCache storage _cache, bytes32 value) internal view returns (bool) {
        return _cache.indices[value] != 0;
    }

    /**
     * @notice Returns all cached values in physical slot order (ring[1]..ring[maxCacheSize]).
     * @param _cache Storage cache struct.
     * @return out Array of length maxCacheSize; removed/empty slots are bytes32(0).
     */
    function all(RingCache storage _cache) internal view returns (bytes32[] memory out) {
        out = new bytes32[](_cache.maxCacheSize);
        for (uint256 i = 0; i < _cache.maxCacheSize; ++i) {
            out[i] = _cache.ring[i + 1];
        }
    }
}
