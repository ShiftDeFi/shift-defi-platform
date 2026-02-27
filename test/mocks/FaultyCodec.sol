// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "contracts/libraries/helpers/Errors.sol";

library FaultyCodec {
    struct DepositRequest {
        address[] tokens;
        uint256[] amounts;
    }

    struct DepositResponse {
        address[] tokens;
        uint256[] amounts;
        uint256 navAH;
        uint256 navAE;
    }

    struct WithdrawalRequest {
        uint256 share;
    }

    struct WithdrawalResponse {
        address[] tokens;
        uint256[] amounts;
    }

    uint8 constant DEPOSIT_REQUEST_TYPE = 0;
    uint8 constant DEPOSIT_RESPONSE_TYPE = 1;
    uint8 constant WITHDRAWAL_REQUEST_TYPE = 2;
    uint8 constant WITHDRAWAL_RESPONSE_TYPE = 3;

    uint256 constant UINT8_SIZE = 1;
    uint256 constant ADDRESS_SIZE = 20;
    uint256 constant UINT128_SIZE = 16;

    uint256 constant MESSAGE_TYPE_POSITION = 0;
    uint256 constant NUM_TOKENS_POSITION = 1;
    uint256 constant ADDRESS_ARRAY_START_POSITION = 2;
    uint256 constant SHARE_POSITION = 1;

    uint256 constant MAX_TOKENS = type(uint8).max;

    // Assembly constants for efficient memory operations
    uint256 constant WORD_SIZE = 32;
    uint256 constant ADDRESS_BITS_SHIFT = 96;
    uint256 constant UINT128_BITS_SHIFT = 128;
    uint256 constant ADDRESS_BYTE_OFFSET = 12;
    uint256 constant UINT128_BYTE_OFFSET = 16;

    error IncorrectMessageType(uint8 messageType);
    error InvalidDataLength();
    error WrongMessageType(uint8 messageType);

    function _writeUint8(bytes memory buffer, uint8 value, uint256 variablePosition) internal pure {
        assembly {
            // Calculate offset: buffer pointer + WORD_SIZE (skip length) + position
            let offset := add(add(buffer, WORD_SIZE), variablePosition)
            // Write single byte at offset
            mstore8(offset, value)
        }
    }

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

    function encode(DepositResponse memory response) internal pure returns (bytes memory) {
        uint256 numTokens = response.tokens.length;
        require(numTokens < MAX_TOKENS, Errors.IncorrectAmount());
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

    function encode(WithdrawalResponse memory response) internal pure returns (bytes memory) {
        uint256 numTokens = response.tokens.length;
        require(numTokens > 0, Errors.ZeroArrayLength());
        require(numTokens < MAX_TOKENS, Errors.IncorrectAmount());
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
}
