// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Errors} from "./helpers/Errors.sol";

/// @title Codec
/// @notice Library for encoding and decoding cross-chain messages for deposit and withdrawal operations
/// @dev Provides efficient binary encoding/decoding with bounds checking and validation
library Codec {
    /// @notice Deposit request structure containing tokens and amounts
    /// @param tokens Array of token addresses to deposit
    /// @param amounts Array of token amounts to deposit (must match tokens length)
    struct DepositRequest {
        address[] tokens;
        uint256[] amounts;
    }

    /// @notice Deposit response structure containing tokens, amounts, and NAV values
    /// @param tokens Array of token addresses received
    /// @param amounts Array of token amounts received (must match tokens length)
    /// @param navAH Net Asset Value for Agent Holdings
    /// @param navAE Net Asset Value for Agent Equity
    struct DepositResponse {
        address[] tokens;
        uint256[] amounts;
        uint256 navAH;
        uint256 navAE;
    }

    /// @notice Withdrawal request structure containing share amount
    /// @param share Amount of shares to withdraw
    struct WithdrawalRequest {
        uint256 share;
    }

    /// @notice Withdrawal response structure containing tokens and amounts
    /// @param tokens Array of token addresses received
    /// @param amounts Array of token amounts received (must match tokens length)
    struct WithdrawalResponse {
        address[] tokens;
        uint256[] amounts;
    }

    /// @notice Message type constants for different message types
    uint8 constant DEPOSIT_REQUEST_TYPE = 0;
    uint8 constant DEPOSIT_RESPONSE_TYPE = 1;
    uint8 constant WITHDRAWAL_REQUEST_TYPE = 2;
    uint8 constant WITHDRAWAL_RESPONSE_TYPE = 3;

    /// @notice Size constants for different data types in bytes
    uint256 constant UINT8_SIZE = 1;
    uint256 constant ADDRESS_SIZE = 20;
    uint256 constant UINT128_SIZE = 16;

    /// @notice Position constants for data layout in encoded messages
    uint256 constant MESSAGE_TYPE_POSITION = 0;
    uint256 constant NUM_TOKENS_POSITION = 1;
    uint256 constant ADDRESS_ARRAY_START_POSITION = 2;
    uint256 constant SHARE_POSITION = 1;

    /// @notice Maximum number of tokens allowed in a single message
    uint256 constant MAX_TOKENS = type(uint8).max;

    // Assembly constants for efficient memory operations
    /// @notice Size of a memory word in bytes (32 bytes)
    uint256 constant WORD_SIZE = 32;
    /// @notice Bits to shift right to extract address from a word (96 bits = 32*8 - 20*8)
    uint256 constant ADDRESS_BITS_SHIFT = 96;
    /// @notice Bits to shift right to extract uint128 from a word (128 bits = 32*8 - 16*8)
    uint256 constant UINT128_BITS_SHIFT = 128;
    /// @notice Byte offset in word for address (12 bytes = 32 - 20)
    uint256 constant ADDRESS_BYTE_OFFSET = 12;
    /// @notice Byte offset in word for uint128 (16 bytes = 32 - 16)
    uint256 constant UINT128_BYTE_OFFSET = 16;

    /// @notice Error thrown when message type doesn't match expected type
    /// @param messageType The incorrect message type received
    error IncorrectMessageType(uint8 messageType);
    /// @notice Error thrown when data length is invalid
    error InvalidDataLength();
    /// @notice Error thrown when message type doesn't match expected type
    error WrongMessageType(uint8 messageType);

    /**
     * @notice Encodes a deposit request into a byte array.
     * @dev Reverts if token list is empty, exceeds MAX_TOKENS, or lengths mismatch.
     * @param request The deposit request to encode.
     * @return Encoded byte array containing message type, token count, addresses, and amounts.
     */
    function encode(DepositRequest memory request) internal pure returns (bytes memory) {
        uint256 numTokens = request.tokens.length;

        require(numTokens > 0, Errors.ZeroArrayLength());
        require(numTokens <= MAX_TOKENS, Errors.IncorrectAmount());
        require(numTokens == request.amounts.length, Errors.ArrayLengthMismatch());

        uint256 tokenAmountsPosition = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE;
        uint256 packageSize = tokenAmountsPosition + numTokens * UINT128_SIZE;

        bytes memory buffer = new bytes(packageSize);
        _writeUint8(buffer, DEPOSIT_REQUEST_TYPE, MESSAGE_TYPE_POSITION);
        _writeUint8(buffer, uint8(numTokens), NUM_TOKENS_POSITION);
        _writeAddressArray(buffer, request.tokens, ADDRESS_ARRAY_START_POSITION);
        _writeUint128Array(buffer, request.amounts, tokenAmountsPosition);

        return buffer;
    }

    /**
     * @notice Encodes a deposit response into a byte array.
     * @dev Reverts if token count exceeds MAX_TOKENS, lengths mismatch, or NAV values exceed uint128.
     * @param response The deposit response to encode.
     * @return Encoded byte array containing message type, token count, addresses, amounts, and NAV values.
     */
    function encode(DepositResponse memory response) internal pure returns (bytes memory) {
        uint256 numTokens = response.tokens.length;

        require(numTokens <= MAX_TOKENS, Errors.IncorrectAmount());
        require(numTokens == response.amounts.length, Errors.ArrayLengthMismatch());
        require(response.navAH <= type(uint128).max, Errors.IncorrectAmount());
        require(response.navAE <= type(uint128).max, Errors.IncorrectAmount());

        uint256 packageSize = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE) + 2 * UINT128_SIZE;
        uint256 navAHPosition = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE + numTokens * UINT128_SIZE;
        uint256 navAEPosition = navAHPosition + UINT128_SIZE;

        bytes memory buffer = new bytes(packageSize);

        _writeUint8(buffer, DEPOSIT_RESPONSE_TYPE, MESSAGE_TYPE_POSITION);
        _writeUint8(buffer, uint8(numTokens), NUM_TOKENS_POSITION);
        if (numTokens > 0) {
            _writeAddressArray(buffer, response.tokens, ADDRESS_ARRAY_START_POSITION);
            _writeUint128Array(buffer, response.amounts, ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE);
        }
        _writeUint128(buffer, uint128(response.navAH), navAHPosition, navAEPosition);
        _writeUint128(buffer, uint128(response.navAE), navAEPosition, navAEPosition + UINT128_SIZE);

        return buffer;
    }

    /**
     * @notice Encodes a withdrawal request into a byte array.
     * @dev Reverts if share does not fit in uint128.
     * @param request The withdrawal request to encode.
     * @return Encoded byte array containing message type and share amount.
     */
    function encode(WithdrawalRequest memory request) internal pure returns (bytes memory) {
        require(request.share <= type(uint128).max, Errors.IncorrectAmount());
        uint256 packageSize = UINT8_SIZE + UINT128_SIZE;
        bytes memory buffer = new bytes(packageSize);

        _writeUint8(buffer, WITHDRAWAL_REQUEST_TYPE, MESSAGE_TYPE_POSITION);
        _writeUint128(buffer, uint128(request.share), SHARE_POSITION, buffer.length);

        return buffer;
    }

    /**
     * @notice Encodes a withdrawal response into a byte array.
     * @dev Reverts if token list is empty, exceeds MAX_TOKENS, or lengths mismatch.
     * @param response The withdrawal response to encode.
     * @return Encoded byte array containing message type, token count, addresses, and amounts.
     */
    function encode(WithdrawalResponse memory response) internal pure returns (bytes memory) {
        uint256 numTokens = response.tokens.length;

        require(numTokens > 0, Errors.ZeroArrayLength());
        require(numTokens <= MAX_TOKENS, Errors.IncorrectAmount());
        require(numTokens == response.amounts.length, Errors.ArrayLengthMismatch());

        uint256 tokenAmountsPosition = 2 * UINT8_SIZE + numTokens * ADDRESS_SIZE;
        uint256 packageSize = tokenAmountsPosition + numTokens * UINT128_SIZE;

        bytes memory buffer = new bytes(packageSize);
        _writeUint8(buffer, WITHDRAWAL_RESPONSE_TYPE, MESSAGE_TYPE_POSITION);
        _writeUint8(buffer, uint8(numTokens), NUM_TOKENS_POSITION);
        if (numTokens > 0) {
            _writeAddressArray(buffer, response.tokens, ADDRESS_ARRAY_START_POSITION);
            _writeUint128Array(buffer, response.amounts, tokenAmountsPosition);
        }

        return buffer;
    }

    /**
     * @notice Decodes a deposit request from a byte array.
     * @dev Reverts on incorrect type, length, or token count.
     * @param data The encoded byte array to decode.
     * @return request Decoded deposit request structure.
     */
    function decodeDepositRequest(bytes memory data) internal pure returns (DepositRequest memory) {
        uint8 messageType = fetchMessageType(data);
        uint8 numTokens = fetchNumTokens(data);

        uint256 expectedLength = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE + numTokens * UINT128_SIZE;
        require(data.length == expectedLength, InvalidDataLength());
        require(messageType == DEPOSIT_REQUEST_TYPE, IncorrectMessageType(messageType));

        return DepositRequest(fetchAddressArray(data, numTokens), fetchUint128Array(data, numTokens));
    }

    /**
     * @notice Decodes a deposit response from a byte array.
     * @dev Reverts on incorrect type, length, or token count.
     * @param data The encoded byte array to decode.
     * @return response Decoded deposit response structure.
     */
    function decodeDepositResponse(bytes memory data) internal pure returns (DepositResponse memory) {
        uint8 messageType = fetchMessageType(data);
        uint8 numTokens = fetchNumTokens(data);
        uint256 navAHPosition = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE + numTokens * UINT128_SIZE;
        uint256 navAEPosition = navAHPosition + UINT128_SIZE;

        uint256 expectedLength = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE) + 2 * UINT128_SIZE;

        require(data.length == expectedLength, InvalidDataLength());
        require(messageType == DEPOSIT_RESPONSE_TYPE, IncorrectMessageType(messageType));

        return
            DepositResponse(
                fetchAddressArray(data, numTokens),
                fetchUint128Array(data, numTokens),
                fetchUint128(data, navAHPosition),
                fetchUint128(data, navAEPosition)
            );
    }

    /**
     * @notice Decodes a withdrawal request from a byte array.
     * @dev Reverts on incorrect type or invalid length.
     * @param data The encoded byte array to decode.
     * @return request Decoded withdrawal request structure.
     */
    function decodeWithdrawalRequest(bytes memory data) internal pure returns (WithdrawalRequest memory) {
        uint8 messageType = fetchMessageType(data);
        require(messageType == WITHDRAWAL_REQUEST_TYPE, IncorrectMessageType(messageType));
        uint256 expectedLength = UINT8_SIZE + UINT128_SIZE;
        require(data.length == expectedLength, InvalidDataLength());
        return WithdrawalRequest(fetchUint128(data, SHARE_POSITION));
    }

    /**
     * @notice Decodes a withdrawal response from a byte array.
     * @dev Reverts on incorrect type, length, or token count.
     * @param data The encoded byte array to decode.
     * @return response Decoded withdrawal response structure.
     */
    function decodeWithdrawalResponse(bytes memory data) internal pure returns (WithdrawalResponse memory) {
        uint8 messageType = fetchMessageType(data);
        uint8 numTokens = fetchNumTokens(data);
        uint256 expectedLength = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE);

        require(data.length == expectedLength, InvalidDataLength());
        require(messageType == WITHDRAWAL_RESPONSE_TYPE, IncorrectMessageType(messageType));

        return WithdrawalResponse(fetchAddressArray(data, numTokens), fetchUint128Array(data, numTokens));
    }

    /**
     * @notice Writes a uint8 value to a specific position in the buffer.
     * @dev Uses assembly for gas efficiency. Skips the length prefix (WORD_SIZE) when calculating offset.
     * @param buffer The byte array buffer to write to.
     * @param value The uint8 value to write.
     * @param variablePosition The position in the buffer to write the value.
     */
    function _writeUint8(bytes memory buffer, uint8 value, uint256 variablePosition) internal pure {
        assembly {
            // Calculate offset: buffer pointer + WORD_SIZE (skip length) + position
            let offset := add(add(buffer, WORD_SIZE), variablePosition)
            // Write single byte at offset
            mstore8(offset, value)
        }
    }

    /**
     * @notice Writes a uint128 value to a specific position range in the buffer.
     * @dev Writes the lower 16 bytes of `value` into [startPosition, endPosition). Requires range length 16 bytes.
     * @param buffer The byte array buffer to write to.
     * @param value The uint128 value to write.
     * @param startPosition The starting position in the buffer.
     * @param endPosition The ending position in the buffer (exclusive).
     */
    function _writeUint128(
        bytes memory buffer,
        uint128 value,
        uint256 startPosition,
        uint256 endPosition
    ) internal pure {
        uint256 delta = endPosition - startPosition;
        assembly {
            // Calculate offset: buffer pointer + WORD_SIZE (skip length) + start position
            let offset := add(add(buffer, WORD_SIZE), startPosition)
            // Loop through each byte in the range
            for {
                let i := 0
            } lt(i, delta) {
                i := add(i, 1)
            } {
                // Extract byte at position (UINT128_BYTE_OFFSET + i) from value and write it
                // UINT128_BYTE_OFFSET = 16, so we extract bytes 16-31 (the 16 bytes of uint128)
                mstore8(offset, byte(add(UINT128_BYTE_OFFSET, i), value))
                offset := add(offset, 1)
            }
        }
    }

    /**
     * @notice Writes an array of addresses to a specific position in the buffer.
     * @dev Writes each address as 20 bytes (no length prefix). Assumes data region is large enough.
     * @param buffer The byte array buffer to write to.
     * @param addresses The array of addresses to write.
     * @param variablePosition The starting position in the buffer.
     */
    function _writeAddressArray(
        bytes memory buffer,
        address[] memory addresses,
        uint256 variablePosition
    ) internal pure {
        uint256 numTokens = addresses.length;
        assembly {
            // Calculate offset: buffer pointer + WORD_SIZE (skip length) + position
            let offset := add(add(buffer, WORD_SIZE), variablePosition)
            // Get pointer to addresses array data (skip length prefix)
            let tokensArrayPtr := add(addresses, WORD_SIZE)

            // Loop through each address
            for {
                let i := 0
            } lt(i, numTokens) {
                i := add(i, 1)
            } {
                // Load word containing address (32 bytes, but address is only 20 bytes)
                let word := mload(add(tokensArrayPtr, mul(i, WORD_SIZE)))
                // Write only the 20 bytes of the address (bytes 12-31, skipping leading zeros)
                for {
                    let k := ADDRESS_BYTE_OFFSET // Start at byte 12
                } lt(k, WORD_SIZE) {
                    k := add(k, 1)
                } {
                    mstore8(offset, byte(k, word))
                    offset := add(offset, 1)
                }
            }
        }
    }

    /**
     * @notice Writes an array of uint256 values as uint128 to a specific position in the buffer.
     * @dev Reverts if any value exceeds uint128. Writes 16 bytes per value starting at variablePosition.
     * @param buffer The byte array buffer to write to.
     * @param values The array of uint256 values to write (must fit in uint128).
     * @param variablePosition The starting position in the buffer.
     */
    function _writeUint128Array(bytes memory buffer, uint256[] memory values, uint256 variablePosition) internal pure {
        uint256 numValues = values.length;
        for (uint256 i = 0; i < numValues; ++i) {
            require(values[i] <= type(uint128).max, Errors.IncorrectAmount());
        }
        assembly {
            // Calculate offset: buffer pointer + WORD_SIZE (skip length) + position
            let offset := add(add(buffer, WORD_SIZE), variablePosition)
            // Get pointer to values array data (skip length prefix)
            let amountsArrayPtr := add(values, WORD_SIZE)
            // Maximum value for uint128: 2^128 - 1
            let max128 := sub(shl(128, 1), 1)

            // Loop through each value
            for {
                let i := 0
            } lt(i, numValues) {
                i := add(i, 1)
            } {
                // Load the value (32 bytes)
                let word := mload(add(amountsArrayPtr, mul(i, WORD_SIZE)))
                // Write only the 16 bytes of uint128 (bytes 16-31, skipping leading zeros)
                for {
                    let k := UINT128_BYTE_OFFSET // Start at byte 16
                } lt(k, WORD_SIZE) {
                    k := add(k, 1)
                } {
                    mstore8(offset, byte(k, word))
                    offset := add(offset, 1)
                }
            }
        }
    }

    /**
     * @notice Fetches the message type from encoded data.
     * @dev Reverts if data too short or message type is outside 0-3 range.
     * @param data The encoded byte array.
     * @return messageType The message type (0-3).
     */
    function fetchMessageType(bytes memory data) internal pure returns (uint8) {
        require(data.length > MESSAGE_TYPE_POSITION, InvalidDataLength());
        uint8 messageType = uint8(data[0]);
        require(messageType <= WITHDRAWAL_RESPONSE_TYPE, IncorrectMessageType(messageType));
        return messageType;
    }

    /**
     * @notice Fetches the number of tokens from encoded data.
     * @dev Reverts if data too short or token count >= MAX_TOKENS.
     * @param data The encoded byte array.
     * @return numTokens The number of tokens (must be < MAX_TOKENS).
     */
    function fetchNumTokens(bytes memory data) internal pure returns (uint8) {
        require(data.length > NUM_TOKENS_POSITION, InvalidDataLength());
        uint8 numTokens = uint8(data[1]);
        require(numTokens < MAX_TOKENS, Errors.IncorrectAmount());
        return numTokens;
    }

    /**
     * @notice Fetches an array of addresses from encoded data.
     * @dev Validates data length before reading. Uses assembly for gas efficiency.
     * @param data The encoded byte array.
     * @param numTokens The number of addresses to read.
     * @return addresses Array of decoded addresses.
     */
    function fetchAddressArray(bytes memory data, uint8 numTokens) internal pure returns (address[] memory) {
        uint256 expectedLength = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE;
        require(data.length >= expectedLength, InvalidDataLength());

        address[] memory addresses = new address[](numTokens);
        if (numTokens == 0) {
            return addresses;
        }
        assembly {
            // Calculate offset: data pointer + WORD_SIZE (skip length) + start position
            let offset := add(add(data, WORD_SIZE), ADDRESS_ARRAY_START_POSITION)
            // Get pointer to addresses array data (skip length prefix)
            let addressesPtr := add(addresses, WORD_SIZE)

            // Loop through each address
            for {
                let i := 0
            } lt(i, numTokens) {
                i := add(i, 1)
            } {
                // Load 32 bytes starting at offset + i * ADDRESS_SIZE
                // This reads 20 bytes of address + 12 bytes of padding
                let word := mload(add(offset, mul(i, ADDRESS_SIZE)))
                // Shift right by 96 bits to extract the 20-byte address (remove padding)
                let addr := shr(ADDRESS_BITS_SHIFT, word)
                // Store the address in the addresses array
                mstore(add(addressesPtr, mul(i, WORD_SIZE)), addr)
            }
        }
        return addresses;
    }

    /**
     * @notice Fetches a uint128 value from encoded data at a specific position.
     * @dev Validates data length before reading. Uses assembly for gas efficiency.
     *      Reads 32 bytes and shifts to extract the 16 bytes of uint128.
     * @param data The encoded byte array.
     * @param position The byte position to read from.
     * @return value The decoded uint128 value (returned as uint256).
     */
    function fetchUint128(bytes memory data, uint256 position) internal pure returns (uint256) {
        // Validate that we have enough data to read UINT128_SIZE bytes starting at position
        require(data.length >= position + UINT128_SIZE, InvalidDataLength());

        uint256 word;
        assembly {
            // Calculate offset: data pointer + WORD_SIZE (skip length) + position
            let offset := add(add(data, WORD_SIZE), position)
            // Load 32 bytes starting at offset
            word := mload(offset)
            // Shift right by 128 bits to extract the 16 bytes of uint128 (remove leading zeros)
            word := shr(UINT128_BITS_SHIFT, word)
        }
        return word;
    }

    /**
     * @notice Fetches an array of uint128 values from encoded data.
     * @dev Validates data length before reading. Uses assembly for gas efficiency.
     *      Assumes addresses come before amounts in the data layout.
     * @param data The encoded byte array.
     * @param numTokens The number of uint128 values to read.
     * @return amounts Array of decoded uint128 values (returned as uint256[]).
     */
    function fetchUint128Array(bytes memory data, uint8 numTokens) internal pure returns (uint256[] memory) {
        uint256 expectedLength = ADDRESS_ARRAY_START_POSITION + numTokens * (ADDRESS_SIZE + UINT128_SIZE);
        require(data.length >= expectedLength, InvalidDataLength());

        uint256[] memory amounts = new uint256[](numTokens);
        // Calculate offset: start position + addresses array size
        uint256 offset = ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE;
        assembly {
            // Calculate actual memory offset: data pointer + WORD_SIZE (skip length) + calculated offset
            offset := add(add(data, WORD_SIZE), offset)
            // Get pointer to amounts array data (skip length prefix)
            let amountsPtr := add(amounts, WORD_SIZE)

            // Loop through each uint128 value
            for {
                let i := 0
            } lt(i, numTokens) {
                i := add(i, 1)
            } {
                // Load 32 bytes starting at offset + i * UINT128_SIZE
                // This reads 16 bytes of uint128 + 16 bytes of padding
                let word := mload(add(offset, mul(i, UINT128_SIZE)))
                // Shift right by 128 bits to extract the 16 bytes of uint128 (remove padding)
                word := shr(UINT128_BITS_SHIFT, word)
                // Store the value in the amounts array
                mstore(add(amountsPtr, mul(i, WORD_SIZE)), word)
            }
        }

        return amounts;
    }
}
