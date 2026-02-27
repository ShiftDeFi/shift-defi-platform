// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Codec} from "contracts/libraries/Codec.sol";

import {L1Base} from "test/L1Base.t.sol";

abstract contract CodecBaseTest is L1Base {
    Codec.DepositRequest internal depositRequest;
    Codec.DepositResponse internal depositResponse;
    Codec.WithdrawalRequest internal withdrawalRequest;
    Codec.WithdrawalResponse internal withdrawalResponse;

    uint256 internal constant MIN_DEPOSIT_REQUEST_SIZE = 38;
    uint256 internal constant MIN_DEPOSIT_RESPONSE_SIZE = 34;
    uint256 internal constant MIN_WITHDRAWAL_REQUEST_SIZE = 17;
    uint256 internal constant MIN_WITHDRAWAL_RESPONSE_SIZE = 38;

    /// @notice Message type constants for different message types
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

    uint256 constant WORD_SIZE = 32;
    uint256 constant ADDRESS_BITS_SHIFT = 96;
    uint256 constant UINT128_BITS_SHIFT = 128;
    uint256 constant ADDRESS_BYTE_OFFSET = 12;
    uint256 constant UINT128_BYTE_OFFSET = 16;

    function setUp() public virtual override {
        super.setUp();
    }
}
