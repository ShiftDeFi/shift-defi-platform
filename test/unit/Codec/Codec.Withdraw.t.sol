// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {Codec} from "contracts/libraries/Codec.sol";

import {CodecBaseTest} from "test/unit/Codec/CodecBase.t.sol";

contract CodecWithdrawTest is CodecBaseTest {
    /// @dev Foundry does not track subsequent state with default.allow_internal_expect_revert = true
    function setUp() public override {
        super.setUp();
    }

    function test_EncodeWithdrawalRequest() public {
        withdrawalRequest.share = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(withdrawalRequest);

        assertGe(encoded.length, MIN_WITHDRAWAL_REQUEST_SIZE, "test_EncodeDecodeWithdrawalRequest: encoded length");

        Codec.WithdrawalRequest memory decoded = Codec.decodeWithdrawalRequest(encoded);
        assertEq(decoded.share, withdrawalRequest.share, "test_EncodeDecodeWithdrawalRequest: decoded share");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeWithdrawalRequest_ShareOutOfBounds() public {
        withdrawalRequest.share = uint256(type(uint128).max) + 1;
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(withdrawalRequest);
    }

    function test_EncodeWithdrawalResponse() public {
        withdrawalResponse.tokens = [address(dai), address(notion)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(withdrawalResponse);

        assertGe(encoded.length, MIN_WITHDRAWAL_RESPONSE_SIZE, "test_EncodeDecodeWithdrawalResponse: encoded length");

        Codec.WithdrawalResponse memory decoded = Codec.decodeWithdrawalResponse(encoded);
        assertEq(
            decoded.tokens.length,
            withdrawalResponse.tokens.length,
            "test_EncodeDecodeWithdrawalResponse: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            withdrawalResponse.amounts.length,
            "test_EncodeDecodeWithdrawalResponse: decoded amounts length"
        );
        for (uint256 i = 0; i < decoded.tokens.length; ++i) {
            assertEq(
                decoded.tokens[i],
                withdrawalResponse.tokens[i],
                "test_EncodeDecodeWithdrawalResponse: decoded token"
            );
            assertEq(
                decoded.amounts[i],
                withdrawalResponse.amounts[i],
                "test_EncodeDecodeWithdrawalResponse: decoded amount"
            );
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeWithdrawalResponse_ZeroTokens() public {
        uint256 length = 0;
        withdrawalResponse.tokens = new address[](length);
        withdrawalResponse.amounts = new uint256[](length);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        Codec.encode(withdrawalResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeWithdrawalResponse_MaxTokens() public {
        uint256 length = MAX_TOKENS + 1;
        withdrawalResponse.tokens = new address[](length);
        withdrawalResponse.amounts = new uint256[](length);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(withdrawalResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeWithdrawalResponse_ArrayLengthMismatch() public {
        withdrawalResponse.tokens = [address(dai), address(notion)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION];
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        Codec.encode(withdrawalResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeWithdrawalResponse_DuplicatingTokens() public {
        withdrawalResponse.tokens = [address(dai), address(dai)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * DAI_PRECISION];
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicatingAddressInArray.selector, address(dai)));
        Codec.encode(withdrawalResponse);
    }

    function test_DecodeWithdrawalRequest() public {
        withdrawalRequest.share = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(withdrawalRequest);
        Codec.WithdrawalRequest memory decoded = Codec.decodeWithdrawalRequest(encoded);
        assertEq(decoded.share, withdrawalRequest.share, "test_DecodeWithdrawalRequest: decoded share");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeWithdrawalRequest_InvalidLength() public {
        bytes memory encoded = Codec.encode(withdrawalRequest);
        // Trim the last 5 bytes from the array
        assembly {
            mstore(encoded, sub(mload(encoded), 5))
        }
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.decodeWithdrawalRequest(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeWithdrawalRequest_IncorrectMessageType() public {
        withdrawalRequest.share = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(withdrawalRequest);
        // Set message type to WithdrawalResponse
        assembly {
            let dataPtr := add(encoded, 0x20)
            mstore8(dataPtr, 3)
        }
        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, 3));
        Codec.decodeWithdrawalRequest(encoded);
    }

    function test_DecodeWithdrawalResponse() public {
        withdrawalResponse.tokens = [address(dai), address(notion)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(withdrawalResponse);
        Codec.WithdrawalResponse memory decoded = Codec.decodeWithdrawalResponse(encoded);
        assertEq(
            decoded.tokens.length,
            withdrawalResponse.tokens.length,
            "test_DecodeWithdrawalResponse: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            withdrawalResponse.amounts.length,
            "test_DecodeWithdrawalResponse: decoded amounts length"
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeWithdrawalResponse_InvalidLength() public {
        withdrawalResponse.tokens = [address(dai), address(notion)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(withdrawalResponse);
        // Trim the last 5 bytes from the array
        assembly {
            mstore(encoded, sub(mload(encoded), 5))
        }
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.decodeWithdrawalResponse(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeWithdrawalResponse_IncorrectMessageType() public {
        withdrawalResponse.tokens = [address(dai), address(notion)];
        withdrawalResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(withdrawalResponse);
        // Set message type to WithdrawalRequest
        assembly {
            let dataPtr := add(encoded, 0x20)
            mstore8(dataPtr, 2)
        }
        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, 2));
        Codec.decodeWithdrawalResponse(encoded);
    }
}
