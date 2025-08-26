// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

library MessageCodec {
    error MessageTooShort(uint256 length);

    function encodeMessage(
        uint256 nonce,
        bytes32 pathOnRemoteChain,
        bytes memory message
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(nonce, pathOnRemoteChain, message);
    }

    function decodeMessage(bytes memory message) internal pure returns (uint256, bytes32, bytes memory) {
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
        bytes memory messageData = new bytes(messageLength);
        assembly {
            // Copy remaining bytes after nonce and path
            let messageStart := add(add(message, 64), 32)
            let messageDataStart := add(messageData, 32)
            for {
                let i := 0
            } lt(i, messageLength) {
                i := add(i, 32)
            } {
                mstore(add(messageDataStart, i), mload(add(messageStart, i)))
            }
        }
        return (nonce, pathOnRemoteChain, messageData);
    }
}
