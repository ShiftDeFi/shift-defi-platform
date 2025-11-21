// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IMessageRouter {
    struct PathData {
        uint256 lastNonce;
        uint256 chainId;
        address sender;
        address receiver;
        bool isWhitelisted;
    }
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
        PathData localPathData;
        PathData remotePathData;
    }

    event MessageSent(
        uint256 nonce,
        uint256 indexed chainTo,
        address indexed sender,
        address indexed receiver,
        address adapter,
        bytes32 localPath,
        bytes32 remotePath
    );
    event MessageReceived(
        uint256 nonce,
        uint256 indexed chainFrom,
        address indexed sender,
        address indexed receiver,
        address adapter,
        bytes32 path
    );
    event MessageRetried(uint256 nonce, uint256 indexed chainTo, bytes32 remotePath, address indexed adapter);
    event MessageRemovedFromCache(bytes32 cacheId, uint256 nonce, uint256 indexed chainId, bytes32 remotePath);
    event AdapterWhitelisted(address adapter);
    event AdapterBlacklisted(address adapter);
    event PathWhitelisted(address indexed sender, address indexed receiver, uint256 indexed chainId, bytes32 path);
    event PathBlacklisted(address indexed sender, address indexed receiver, uint256 indexed chainId, bytes32 path);

    error UnsupportedAdapter(address);
    error InvalidPath(bytes32 path);
    error ReplayCheckFailed(uint256 nonce);
    error MessageTooShort(uint256 length);

    function whitelistPath(address sender, address receiver, uint256 chainId) external;

    function blacklistPath(address sender, address receiver, uint256 chainId) external;

    function whitelistMessageAdapter(address adapter) external;

    function blacklistMessageAdapter(address adapter) external;

    function send(address receiver, SendParams calldata sendParams) external payable;

    function receiveMessage(bytes memory rawMessage) external;

    function retryCachedMessage(uint256 nonce_, bytes32 path, SendParams calldata sendParams) external payable;

    function removeMessageFromCache(uint256 nonce, uint256 chainTo, bytes32 path, bytes memory message) external;

    function isMessageCached(
        uint256 chainTo,
        uint256 nonce,
        bytes32 remotePath,
        bytes memory message
    ) external view returns (bool);
}
