// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IMessageRouter {
    struct SendParams {
        address adapter;
        uint256 chainTo;
        bytes adapterParameters;
        bytes message;
    }

    struct SendLocalVars {
        bytes32 localPath;
        bytes32 remotePath;
        uint256 nonce;
        bytes rawMessageWithPathAndNonce;
    }

    event MessageSent(
        uint256 nonce,
        uint256 chainTo,
        address indexed sender,
        address indexed receiver,
        address adapter
    );
    event MessageReceived(uint256 nonce, bytes32 path, address indexed receiver, address indexed adapter);
    event MessageRetried(uint256 nonce, uint256 chainTo, bytes32 remotePath, address indexedadapter);
    event MessageRemovedFromCache(uint256 nonce, uint256 chainId, bytes32 remotePath);
    event AdapterWhitelisted(address adapter);
    event AdapterBlacklisted(address adapter);
    event PathWhitelisted(address sender, address receiver, uint256 chainId, bytes32 path);
    event PathBlacklisted(address sender, address receiver, uint256 chainId, bytes32 path);
    event ReceiverSet(address sender, address receiver, uint256 chainId, bytes32 path);

    error UnsupportedAdapter(address);
    error InvalidPath(bytes32);
    error ReceiverNotSet(bytes32);
    error AdapterNotWhitelisted(address);
    error InvalidParams(bytes32, bytes32);
    error ReplayCheckFailed(uint256 _nonce);
    error MessageTooShort(uint256 length);

    function whitelistPath(address sender, address receiver, uint256 chainId) external;

    function blacklistPath(address sender, address receiver, uint256 chainId) external;

    function whitelistMessageAdapter(address adapter) external;

    function blacklistMessageAdapter(address adapter) external;

    function setReceiver(address sender, address receiver, uint256 chainId) external;

    function send(address receiver, SendParams calldata sendParams) external payable;

    function receiveMessage(bytes memory rawMessage) external;

    function retryCachedMessage(uint256 nonce_, bytes32 path, SendParams calldata sendParams) external payable;

    function removeMessageFromCache(uint256 _nonce, uint256 chainTo, bytes32 path, bytes memory message) external;
}
