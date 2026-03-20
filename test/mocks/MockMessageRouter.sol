// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";
import {RingCacheLibrary} from "contracts/libraries/RingCacheLibrary.sol";

contract MockMessageRouter is IMessageRouter {
    using RingCacheLibrary for RingCacheLibrary.RingCache;

    uint256 private _nonce;

    mapping(bytes32 => PathData) private _paths;
    mapping(address => bool) private _whitelistedMessageAdapters;

    RingCacheLibrary.RingCache private _sendMessagesCache;

    constructor(uint256 maxCacheSize) {
        _sendMessagesCache.initialize(keccak256("SEND_CACHE"), maxCacheSize);
    }

    function calculatePath(address sender, address receiver, uint256 chainId) public pure returns (bytes32) {
        return keccak256(abi.encode(sender, receiver, chainId));
    }

    function encodeMessage(uint256 nonce, bytes32 path, bytes memory message) public pure returns (bytes memory) {
        return abi.encodePacked(nonce, path, message);
    }

    function calculateCacheKey(uint256 chainTo, bytes memory rawMessageWithPathAndNonce) public pure returns (bytes32) {
        return keccak256(abi.encode(chainTo, rawMessageWithPathAndNonce));
    }

    function decodeMessage(bytes memory) external pure override returns (uint256, bytes32, bytes memory) {}

    function whitelistPath(address, address, uint256) external override {}

    function blacklistPath(address, address, uint256) external override {}

    function whitelistMessageAdapter(address) external override {}

    function blacklistMessageAdapter(address) external override {}

    function send(address receiver, SendParams calldata sendParams) external payable override {
        SendLocalVars memory sendLocalVars;
        sendLocalVars.localPath = calculatePath(msg.sender, receiver, sendParams.chainTo);
        sendLocalVars.remotePath = calculatePath(msg.sender, receiver, block.chainid);
        sendLocalVars.localPathData = _paths[sendLocalVars.localPath];
        sendLocalVars.remotePathData = _paths[sendLocalVars.remotePath];
        sendLocalVars.nonce = ++_nonce;

        sendLocalVars.rawMessageWithPathAndNonce = encodeMessage(
            sendLocalVars.nonce,
            sendLocalVars.remotePath,
            sendParams.message
        );

        _cacheMessage(sendParams.chainTo, sendLocalVars.rawMessageWithPathAndNonce);
    }

    function receiveMessage(bytes memory) external override {}

    function retryCachedMessage(uint256, bytes32, SendParams calldata) external payable override {}

    function removeMessageFromCache(uint256, uint256, bytes32, bytes memory) external override {}

    function isMessageCached(
        uint256 chainTo,
        uint256 nonce,
        bytes32 remotePath,
        bytes memory message
    ) external view returns (bool) {
        bytes memory messageWithNonceAndPath = encodeMessage(nonce, remotePath, message);
        bytes32 cacheKey = calculateCacheKey(chainTo, messageWithNonceAndPath);
        return _sendMessagesCache.exists(cacheKey);
    }

    function _cacheMessage(uint256 chainTo, bytes memory rawMessageWithPathAndNonce) private {
        bytes32 cachedData = calculateCacheKey(chainTo, rawMessageWithPathAndNonce);
        _sendMessagesCache.add(cachedData);

        emit RingCacheLibrary.CacheStored(_sendMessagesCache.id, cachedData);
    }
}
