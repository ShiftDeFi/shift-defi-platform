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

    /**
     * @notice Calculates the path identifier from sender/receiver/chain.
     * @param sender Message sender.
     * @param receiver Message receiver.
     * @param chainId Destination chain id.
     */
    function calculatePath(address sender, address receiver, uint256 chainId) external pure returns (bytes32);

    /**
     * @notice ABI-encodes nonce + path + message.
     * @param nonce Message nonce.
     * @param path Remote path.
     * @param message Message bytes.
     */
    function encodeMessage(uint256 nonce, bytes32 path, bytes memory message) external pure returns (bytes memory);

    /**
     * @notice Calculates cache key for cached message.
     * @param chainTo Destination chain id.
     * @param rawMessageWithPathAndNonce Encoded message with path and nonce.
     */
    function calculateCacheKey(
        uint256 chainTo,
        bytes memory rawMessageWithPathAndNonce
    ) external pure returns (bytes32);

    /**
     * @notice Decodes encoded message into nonce, path and payload.
     * @param message Encoded message bytes.
     */
    function decodeMessage(bytes memory message) external view returns (uint256, bytes32, bytes memory);

    /**
     * @notice Whitelists a message path.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param sender The address of the message sender
     * @param receiver The address of the message receiver
     * @param chainId The destination chain ID
     */
    function whitelistPath(address sender, address receiver, uint256 chainId) external;

    /**
     * @notice Blacklists a message path.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param sender The address of the message sender
     * @param receiver The address of the message receiver
     * @param chainId The destination chain ID
     */
    function blacklistPath(address sender, address receiver, uint256 chainId) external;

    /**
     * @notice Whitelists a message adapter.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param adapter The address of the message adapter
     */
    function whitelistMessageAdapter(address adapter) external;

    /**
     * @notice Blacklists a message adapter.
     * @dev Can only be called by accounts with GOVERNANCE_ROLE.
     * @param adapter The address of the message adapter
     */
    function blacklistMessageAdapter(address adapter) external;

    /**
     * @notice Sends a cross-chain message.
     * @dev Requires the path to be whitelisted and the adapter to be whitelisted.
     * @param receiver The address of the receiver on the destination chain
     * @param sendParams The parameters for sending the message
     */
    function send(address receiver, SendParams calldata sendParams) external payable;

    /**
     * @notice Receives a cross-chain message.
     * @dev Can only be called by whitelisted message adapters.
     * @param rawMessage The raw message bytes
     */
    function receiveMessage(bytes memory rawMessage) external;

    /**
     * @notice Retries sending a cached message.
     * @dev Can only be called by accounts with MANAGER_ROLE.
     * @param nonce_ The nonce of the message to retry
     * @param path The path of the message
     * @param sendParams The parameters for sending the message
     */
    function retryCachedMessage(uint256 nonce_, bytes32 path, SendParams calldata sendParams) external payable;

    /**
     * @notice Removes a message from the cache.
     * @dev Can only be called by accounts with MANAGER_ROLE.
     * @param nonce The nonce of the message
     * @param chainTo The destination chain ID
     * @param path The path of the message
     * @param message The message bytes
     */
    function removeMessageFromCache(uint256 nonce, uint256 chainTo, bytes32 path, bytes memory message) external;

    /**
     * @notice Checks if a message is cached.
     * @param chainTo The destination chain ID
     * @param nonce The nonce of the message
     * @param remotePath The remote path
     * @param message The message bytes
     * @return True if the message is cached, false otherwise
     */
    function isMessageCached(
        uint256 chainTo,
        uint256 nonce,
        bytes32 remotePath,
        bytes memory message
    ) external view returns (bool);
}
