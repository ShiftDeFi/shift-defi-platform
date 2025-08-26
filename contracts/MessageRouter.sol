// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMessageRouter} from "./interfaces/IMessageRouter.sol";
import {IMessageReceiver} from "./interfaces/IMessageReceiver.sol";
import {IMessageAdapter} from "./interfaces/IMessageAdapter.sol";
import {RingCacheLibrary} from "./libraries/helpers/RingCacheLibrary.sol";
import {MessageCodec} from "./libraries/MessageCodec.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract MessageRouter is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IMessageRouter {
    using RingCacheLibrary for RingCacheLibrary.RingCache;

    bytes32 private constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 private nonce;

    mapping(address => bool) private _whitelistedMessageAdapters;
    mapping(bytes32 => bool) private _whitelistedPaths;
    mapping(bytes32 => address) private _receivers;
    mapping(bytes32 => uint256) private _lastNonces;

    RingCacheLibrary.RingCache private _cache;

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

        _cache.initialize(maxCacheSize);
    }

    function whitelistPath(address sender, address receiver, uint256 chainId) external onlyRole(GOVERNANCE_ROLE) {
        require(sender != address(0), Errors.ZeroAddress());
        require(receiver != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());

        bytes32 path = keccak256(abi.encodePacked(sender, receiver, chainId));

        require(!_whitelistedPaths[path], Errors.AlreadyWhitelisted());

        _whitelistedPaths[path] = true;
        _lastNonces[path] = 0;

        emit PathWhitelisted(sender, receiver, chainId, path);
    }

    function blacklistPath(address sender, address receiver, uint256 chainId) external onlyRole(GOVERNANCE_ROLE) {
        require(sender != address(0), Errors.ZeroAddress());
        require(receiver != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());

        bytes32 path = keccak256(abi.encodePacked(sender, receiver, chainId));

        require(_whitelistedPaths[path], Errors.AlreadyBlacklisted());

        _whitelistedPaths[path] = false;
        _lastNonces[path] = 0;

        emit PathBlacklisted(sender, receiver, chainId, path);
    }

    function setReceiver(address sender, address receiver, uint256 chainId) external onlyRole(GOVERNANCE_ROLE) {
        require(sender != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());

        bytes32 path = keccak256(abi.encodePacked(sender, receiver, chainId));

        _receivers[path] = receiver;

        emit ReceiverSet(sender, receiver, chainId, path);
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
        uint256 nonce_,
        bytes32 path,
        bytes memory message
    ) external view returns (bool) {
        bytes memory messageWithNonceAndPath = MessageCodec.encodeMessage(nonce_, path, message);
        bytes32 cacheKey = keccak256(abi.encodePacked(chainTo, messageWithNonceAndPath));
        return _cache.exists(cacheKey);
    }

    function send(address receiver, SendParams calldata sendParams) external payable override nonReentrant {
        require(receiver != address(0), Errors.ZeroAddress());
        require(sendParams.chainTo > 0, Errors.ZeroAmount());
        require(_whitelistedMessageAdapters[sendParams.adapter], UnsupportedAdapter(sendParams.adapter));

        SendLocalVars memory sendLocalVars;
        sendLocalVars.localPath = keccak256(abi.encodePacked(msg.sender, receiver, sendParams.chainTo));
        sendLocalVars.nonce = ++nonce;
        sendLocalVars.remotePath = keccak256(abi.encodePacked(msg.sender, receiver, block.chainid));

        require(_whitelistedPaths[sendLocalVars.localPath], InvalidPath(sendLocalVars.localPath));

        sendLocalVars.rawMessageWithPathAndNonce = MessageCodec.encodeMessage(
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

        emit MessageSent(sendLocalVars.nonce, sendParams.chainTo, msg.sender, receiver, sendParams.adapter);
    }

    function receiveMessage(bytes memory rawMessageWithPathAndNonce) external override nonReentrant {
        (uint256 _nonce, bytes32 path, bytes memory rawMessage) = MessageCodec.decodeMessage(
            rawMessageWithPathAndNonce
        );

        require(_nonce > _lastNonces[path], ReplayCheckFailed(_nonce));
        require(_whitelistedMessageAdapters[msg.sender], UnsupportedAdapter(msg.sender));
        require(_receivers[path] != address(0), ReceiverNotSet(path));

        _lastNonces[path] = _nonce;
        IMessageReceiver(_receivers[path]).receiveMessage(rawMessage);

        emit MessageReceived(_nonce, path, _receivers[path], msg.sender);
    }

    function retryCachedMessage(
        uint256 nonce_,
        bytes32 path,
        SendParams calldata sendParams
    ) external payable override nonReentrant onlyRole(MANAGER_ROLE) {
        require(_whitelistedMessageAdapters[sendParams.adapter], UnsupportedAdapter(sendParams.adapter));

        bytes memory messageWithPathAndNonce = MessageCodec.encodeMessage(nonce_, path, sendParams.message);
        bytes32 cachedKey = keccak256(abi.encodePacked(sendParams.chainTo, messageWithPathAndNonce));

        require(_cache.exists(cachedKey), RingCacheLibrary.DoesNotExists(cachedKey));

        IMessageAdapter(sendParams.adapter).send{value: msg.value}(
            sendParams.chainTo,
            sendParams.adapterParameters,
            messageWithPathAndNonce
        );
        emit MessageRetried(nonce_, sendParams.chainTo, path, sendParams.adapter);
    }

    function removeMessageFromCache(
        uint256 _nonce,
        uint256 chainTo,
        bytes32 path,
        bytes memory message
    ) external override onlyRole(MANAGER_ROLE) {
        bytes memory messageWithPathAndNonce = MessageCodec.encodeMessage(_nonce, path, message);
        _removeFromCache(chainTo, messageWithPathAndNonce);
        emit MessageRemovedFromCache(_nonce, chainTo, path);
    }

    function _cacheMessage(uint256 chainTo, bytes memory rawMessageWithPathAndNonce) private {
        bytes32 cached = keccak256(abi.encodePacked(chainTo, rawMessageWithPathAndNonce));
        _cache.add(cached);
        emit RingCacheLibrary.CacheStored(cached);
    }

    function _removeFromCache(uint256 chainTo, bytes memory rawMessageWithPath) private {
        bytes32 cachedKey = keccak256(abi.encodePacked(chainTo, rawMessageWithPath));
        require(_cache.exists(cachedKey), RingCacheLibrary.DoesNotExists(cachedKey));
        _cache.remove(cachedKey);
        emit RingCacheLibrary.CacheEvicted(cachedKey);
    }
}
