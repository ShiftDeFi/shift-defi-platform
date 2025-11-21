// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMessageRouter} from "./interfaces/IMessageRouter.sol";
import {IMessageReceiver} from "./interfaces/IMessageReceiver.sol";
import {IMessageAdapter} from "./interfaces/IMessageAdapter.sol";
import {RingCacheLibrary} from "./libraries/helpers/RingCacheLibrary.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract MessageRouter is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IMessageRouter {
    using RingCacheLibrary for RingCacheLibrary.RingCache;

    bytes32 private constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 private _nonce;

    mapping(bytes32 => PathData) private _paths;
    mapping(address => bool) private _whitelistedMessageAdapters;

    RingCacheLibrary.RingCache private _sendMessagesCache;

    function initialize(
        address defaultAdmin,
        address governance,
        address manager,
        uint256 maxCacheSize
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNANCE_ROLE, governance);
        _grantRole(MANAGER_ROLE, manager);

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

    function decodeMessage(bytes memory message) public view returns (uint256, bytes32, bytes memory) {
        require(message.length >= 64, MessageTooShort(message.length));
        // Extract nonce (uint256 = 32 bytes)
        uint256 nonce;
        assembly {
            nonce := mload(add(message, 32))
        }

        // Extract path (bytes32 = 32 bytes)
        bytes32 pathOnRemoteChain;
        assembly {
            pathOnRemoteChain := mload(add(message, 64))
        }

        // Extract remaining message bytes
        uint256 messageLength = message.length - 64; // Total length minus nonce and path
        if (messageLength == 0) {
            return (nonce, pathOnRemoteChain, new bytes(0));
        }
        bytes memory messageData = new bytes(messageLength);
        assembly {
            let src := add(message, 96)
            let dst := add(messageData, 32)
            let success := staticcall(gas(), 0x04, src, messageLength, dst, messageLength)
            if iszero(success) {
                revert(0, 0)
            }
        }
        return (nonce, pathOnRemoteChain, messageData);
    }

    function whitelistPath(address sender, address receiver, uint256 chainId) external onlyRole(GOVERNANCE_ROLE) {
        require(sender != address(0), Errors.ZeroAddress());
        require(receiver != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());

        bytes32 path = calculatePath(sender, receiver, chainId);
        PathData memory pathData = _paths[path];
        require(!pathData.isWhitelisted, Errors.AlreadyWhitelisted());
        _paths[path] = PathData({
            lastNonce: pathData.lastNonce,
            chainId: chainId,
            sender: sender,
            receiver: receiver,
            isWhitelisted: true
        });
        emit PathWhitelisted(sender, receiver, chainId, path);
    }

    function blacklistPath(address sender, address receiver, uint256 chainId) external onlyRole(GOVERNANCE_ROLE) {
        bytes32 path = calculatePath(sender, receiver, chainId);
        PathData memory pathData = _paths[path];
        require(pathData.isWhitelisted, InvalidPath(path));
        _paths[path].isWhitelisted = false;
        emit PathBlacklisted(pathData.sender, pathData.receiver, pathData.chainId, path);
    }

    function whitelistMessageAdapter(address adapter) external onlyRole(GOVERNANCE_ROLE) {
        require(!_whitelistedMessageAdapters[adapter], Errors.AlreadyWhitelisted());
        _whitelistedMessageAdapters[adapter] = true;
        emit AdapterWhitelisted(adapter);
    }

    function blacklistMessageAdapter(address adapter) external onlyRole(GOVERNANCE_ROLE) {
        require(_whitelistedMessageAdapters[adapter], Errors.AlreadyBlacklisted());
        _whitelistedMessageAdapters[adapter] = false;
        emit AdapterBlacklisted(adapter);
    }

    function isMessageCached(
        uint256 chainTo,
        uint256 nonce,
        bytes32 remotePath,
        bytes memory message
    ) external view override returns (bool) {
        bytes memory messageWithNonceAndPath = encodeMessage(nonce, remotePath, message);
        bytes32 cacheKey = calculateCacheKey(chainTo, messageWithNonceAndPath);
        return _sendMessagesCache.exists(cacheKey);
    }

    function send(address receiver, SendParams calldata sendParams) external payable override nonReentrant {
        require(_whitelistedMessageAdapters[sendParams.adapter], UnsupportedAdapter(sendParams.adapter));

        SendLocalVars memory sendLocalVars;
        sendLocalVars.localPath = calculatePath(msg.sender, receiver, sendParams.chainTo);
        sendLocalVars.remotePath = calculatePath(msg.sender, receiver, block.chainid);
        sendLocalVars.localPathData = _paths[sendLocalVars.localPath];
        sendLocalVars.remotePathData = _paths[sendLocalVars.remotePath];
        sendLocalVars.nonce = ++_nonce;

        require(sendLocalVars.localPathData.isWhitelisted, InvalidPath(sendLocalVars.localPath));
        require(sendLocalVars.localPathData.receiver == receiver, InvalidPath(sendLocalVars.localPath));

        sendLocalVars.rawMessageWithPathAndNonce = encodeMessage(
            sendLocalVars.nonce,
            sendLocalVars.remotePath,
            sendParams.message
        );

        IMessageAdapter(sendParams.adapter).send{value: msg.value}(
            sendParams.chainTo,
            sendParams.adapterParameters,
            sendLocalVars.rawMessageWithPathAndNonce
        );
        _cacheMessage(sendParams.chainTo, sendLocalVars.rawMessageWithPathAndNonce);

        emit MessageSent(
            sendLocalVars.nonce,
            sendParams.chainTo,
            msg.sender,
            receiver,
            sendParams.adapter,
            sendLocalVars.localPath,
            sendLocalVars.remotePath
        );
    }

    function receiveMessage(bytes memory rawMessageWithPathAndNonce) external override nonReentrant {
        (uint256 nonce, bytes32 path, bytes memory rawMessage) = decodeMessage(rawMessageWithPathAndNonce);
        PathData memory pathData = _paths[path];

        require(nonce > pathData.lastNonce, ReplayCheckFailed(nonce));
        require(_whitelistedMessageAdapters[msg.sender], UnsupportedAdapter(msg.sender));
        require(pathData.isWhitelisted, InvalidPath(path));

        _paths[path].lastNonce = nonce;
        IMessageReceiver(pathData.receiver).receiveMessage(rawMessage);

        _cacheMessage(pathData.chainId, rawMessageWithPathAndNonce);

        emit MessageReceived(nonce, pathData.chainId, pathData.sender, pathData.receiver, msg.sender, path);
    }

    function retryCachedMessage(
        uint256 nonce,
        bytes32 path,
        SendParams calldata sendParams
    ) external payable override nonReentrant onlyRole(MANAGER_ROLE) {
        require(_whitelistedMessageAdapters[sendParams.adapter], UnsupportedAdapter(sendParams.adapter));

        bytes memory messageWithPathAndNonce = encodeMessage(nonce, path, sendParams.message);
        bytes32 cachedKey = calculateCacheKey(sendParams.chainTo, messageWithPathAndNonce);

        require(_sendMessagesCache.exists(cachedKey), RingCacheLibrary.DoesNotExists(_sendMessagesCache.id, cachedKey));

        IMessageAdapter(sendParams.adapter).send{value: msg.value}(
            sendParams.chainTo,
            sendParams.adapterParameters,
            messageWithPathAndNonce
        );

        emit MessageRetried(nonce, sendParams.chainTo, path, sendParams.adapter);
    }

    function removeMessageFromCache(
        uint256 nonce,
        uint256 chainTo,
        bytes32 path,
        bytes memory message
    ) external override onlyRole(MANAGER_ROLE) {
        bytes memory messageWithPathAndNonce = encodeMessage(nonce, path, message);
        _removeFromCache(chainTo, messageWithPathAndNonce);
        emit MessageRemovedFromCache(_sendMessagesCache.id, nonce, chainTo, path);
    }

    function _cacheMessage(uint256 chainTo, bytes memory rawMessageWithPathAndNonce) private {
        bytes32 cachedData = calculateCacheKey(chainTo, rawMessageWithPathAndNonce);
        _sendMessagesCache.add(cachedData);
        emit RingCacheLibrary.CacheStored(_sendMessagesCache.id, cachedData);
    }

    function _removeFromCache(uint256 chainTo, bytes memory rawMessageWithPath) private {
        bytes32 cachedKey = calculateCacheKey(chainTo, rawMessageWithPath);
        require(_sendMessagesCache.exists(cachedKey), RingCacheLibrary.DoesNotExists(_sendMessagesCache.id, cachedKey));
        _sendMessagesCache.remove(cachedKey);
        emit RingCacheLibrary.CacheEvicted(_sendMessagesCache.id, cachedKey);
    }
}
