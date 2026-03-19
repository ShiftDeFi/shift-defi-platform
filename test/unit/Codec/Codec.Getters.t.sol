// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Codec} from "contracts/libraries/Codec.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {CodecBaseTest} from "test/unit/Codec/CodecBase.t.sol";

contract CodecGettersTest is CodecBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_FetchMessageType() public pure {
        bytes memory buffer = new bytes(1);
        assembly {
            mstore8(add(buffer, WORD_SIZE), DEPOSIT_REQUEST_TYPE)
        }
        uint8 fetchedMessageType = Codec.fetchMessageType(buffer);
        assertEq(fetchedMessageType, DEPOSIT_REQUEST_TYPE, "test_FetchMessageType: message type");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchMessageType_InvalidLength() public {
        bytes memory buffer = new bytes(0);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.fetchMessageType(buffer);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchMessageType_IncorrectMessageType() public {
        bytes memory buffer = new bytes(1);
        assembly {
            mstore8(add(buffer, WORD_SIZE), add(WITHDRAWAL_RESPONSE_TYPE, 1))
        }
        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, WITHDRAWAL_RESPONSE_TYPE + 1));
        Codec.fetchMessageType(buffer);
    }

    function test_FetchNumTokens() public pure {
        uint256 numTokens = 2;
        bytes memory buffer = new bytes(2);
        assembly {
            mstore8(add(buffer, add(WORD_SIZE, UINT8_SIZE)), numTokens)
        }
        uint8 fetchedNumTokens = Codec.fetchNumTokens(buffer);
        assertEq(fetchedNumTokens, numTokens, "test_FetchNumTokens: num tokens");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchNumTokens_InvalidLength() public {
        bytes memory buffer = new bytes(1);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.fetchNumTokens(buffer);
    }

    function test_FetchAddressArray() public view {
        uint8 numTokens = 2;
        address[] memory addresses = new address[](numTokens);
        addresses[0] = address(dai);
        addresses[1] = address(notion);
        uint256 messageLength = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE);
        bytes memory buffer = new bytes(messageLength);

        Codec._writeAddressArray(buffer, addresses, ADDRESS_ARRAY_START_POSITION);

        address[] memory fetchedAddresses = Codec.fetchAddressArray(buffer, numTokens);
        assertEq(fetchedAddresses[0], addresses[0], "test_FetchAddressArray: address 0");
        assertEq(fetchedAddresses[1], addresses[1], "test_FetchAddressArray: address 1");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchAddressArray_InvalidLength() public {
        bytes memory buffer = new bytes(1);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.fetchAddressArray(buffer, 1);
    }

    function test_FetchUint128() public pure {
        uint128 value = 1000;
        bytes memory buffer = new bytes(WORD_SIZE + UINT128_SIZE);
        Codec._writeUint128(buffer, value, SHARE_POSITION, WORD_SIZE + UINT128_SIZE);
        uint256 fetchedValue = Codec.fetchUint128(buffer, SHARE_POSITION);
        assertEq(fetchedValue, value, "test_FetchUint128: value");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchUint128_InvalidLength() public {
        bytes memory buffer = new bytes(1);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.fetchUint128(buffer, 0);
    }

    function test_FetchUint128Array() public pure {
        uint8 numTokens = 2;
        uint256[] memory values = new uint256[](numTokens);
        values[0] = 1000;
        values[1] = 2000;
        uint256 messageLength = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE);
        bytes memory buffer = new bytes(messageLength);
        Codec._writeUint128Array(buffer, values, ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE);

        uint256[] memory fetchedValues = Codec.fetchUint128Array(buffer, numTokens);
        assertEq(fetchedValues[0], values[0], "test_FetchUint128Array: value 0");
        assertEq(fetchedValues[1], values[1], "test_FetchUint128Array: value 1");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_FetchUint128Array_InvalidLength() public {
        bytes memory buffer = new bytes(1);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.fetchUint128Array(buffer, 1);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_WriteUint128Array_Uint128Overflow() public {
        uint8 numTokens = 1;
        uint256[] memory values = new uint256[](numTokens);
        values[0] = uint256(type(uint128).max) + 1;
        uint256 messageLength = 2 * UINT8_SIZE + numTokens * (ADDRESS_SIZE + UINT128_SIZE);
        bytes memory buffer = new bytes(messageLength);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec._writeUint128Array(buffer, values, ADDRESS_ARRAY_START_POSITION + numTokens * ADDRESS_SIZE);
    }
}
