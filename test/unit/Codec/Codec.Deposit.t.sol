// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {Codec} from "contracts/libraries/Codec.sol";
import {Common} from "contracts/libraries/helpers/Common.sol";

import {CodecBaseTest} from "test/unit/Codec/CodecBase.t.sol";

contract CodecDepositTest is CodecBaseTest {
    /// @dev Foundry does not track subsequent state with default.allow_internal_expect_revert = true
    function setUp() public override {
        super.setUp();
    }

    function test_EncodeDepositRequest() public {
        depositRequest.tokens = [address(dai), address(notion)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(depositRequest);

        assertGe(encoded.length, MIN_DEPOSIT_REQUEST_SIZE, "test_EncodeDepositRequest: encoded length");

        Codec.DepositRequest memory decoded = Codec.decodeDepositRequest(encoded);
        assertEq(
            decoded.tokens.length,
            depositRequest.tokens.length,
            "test_EncodeDepositRequest: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            depositRequest.amounts.length,
            "test_EncodeDepositRequest: decoded amounts length"
        );
        for (uint256 i = 0; i < decoded.tokens.length; ++i) {
            assertEq(decoded.tokens[i], depositRequest.tokens[i], "test_EncodeDepositRequest: decoded token");
            assertEq(decoded.amounts[i], depositRequest.amounts[i], "test_EncodeDepositRequest: decoded amount");
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositRequest_ZeroTokens() public {
        uint256 length = 0;
        depositRequest.tokens = new address[](length);
        depositRequest.amounts = new uint256[](length);

        vm.expectRevert(Errors.ZeroArrayLength.selector);
        Codec.encode(depositRequest);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositRequest_MaxTokens() public {
        uint256 length = MAX_TOKENS + 1;
        depositRequest.tokens = new address[](length);
        depositRequest.amounts = new uint256[](length);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(depositRequest);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositRequest_ArrayLengthMismatch() public {
        depositRequest.tokens = [address(dai), address(notion)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION];
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        Codec.encode(depositRequest);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositRequest_DuplicatingTokens() public {
        depositRequest.tokens = [address(dai), address(dai)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * DAI_PRECISION];
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicatingAddressInArray.selector, address(dai)));
        Codec.encode(depositRequest);
    }

    function test_EncodeDepositResponse() public {
        uint256 nav0 = Common.toUnifiedDecimalsUint8(address(notion), 1_000 * NOTION_PRECISION);
        uint256 nav1 = Common.toUnifiedDecimalsUint8(address(notion), 1_000_000 * NOTION_PRECISION);

        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAH = nav0;
        depositResponse.navAE = nav1;
        bytes memory encoded = Codec.encode(depositResponse);

        assertGe(encoded.length, MIN_DEPOSIT_RESPONSE_SIZE, "test_EncodeDepositResponse: encoded length");

        Codec.DepositResponse memory decoded = Codec.decodeDepositResponse(encoded);
        assertEq(
            decoded.tokens.length,
            depositResponse.tokens.length,
            "test_EncodeDepositResponse: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            depositResponse.amounts.length,
            "test_EncodeDepositResponse: decoded amounts length"
        );
        for (uint256 i = 0; i < decoded.tokens.length; ++i) {
            assertEq(decoded.tokens[i], depositResponse.tokens[i], "test_EncodeDepositResponse: decoded token");
            assertEq(decoded.amounts[i], depositResponse.amounts[i], "test_EncodeDepositResponse: decoded amount");
        }

        assertEq(decoded.navAH, depositResponse.navAH, "test_EncodeDepositResponse: decoded navAH");
        assertEq(decoded.navAE, depositResponse.navAE, "test_EncodeDepositResponse: decoded navAE");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositResponse_MaxTokens() public {
        uint256 length = MAX_TOKENS + 1;
        depositResponse.tokens = new address[](length);
        depositResponse.amounts = new uint256[](length);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(depositResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositResponse_ArrayLengthMismatch() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION];
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        Codec.encode(depositResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositResponse_DuplicatingTokens() public {
        depositResponse.tokens = [address(dai), address(dai)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * DAI_PRECISION];
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicatingAddressInArray.selector, address(dai)));
        Codec.encode(depositResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositResponse_NavAHOutOfBounds() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAH = uint256(type(uint128).max) + 1;
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(depositResponse);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_EncodeDepositResponse_NavAEOutOfBounds() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAE = uint256(type(uint128).max) + 1;
        vm.expectRevert(Errors.IncorrectAmount.selector);
        Codec.encode(depositResponse);
    }

    function test_DecodeDepositRequest() public {
        depositRequest.tokens = [address(dai), address(notion)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(depositRequest);
        Codec.DepositRequest memory decoded = Codec.decodeDepositRequest(encoded);
        assertEq(
            decoded.tokens.length,
            depositRequest.tokens.length,
            "test_DecodeDepositRequest: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            depositRequest.amounts.length,
            "test_DecodeDepositRequest: decoded amounts length"
        );
        for (uint256 i = 0; i < decoded.tokens.length; ++i) {
            assertEq(decoded.tokens[i], depositRequest.tokens[i], "test_DecodeDepositRequest: decoded token");
            assertEq(decoded.amounts[i], depositRequest.amounts[i], "test_DecodeDepositRequest: decoded amount");
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeDepositRequest_InvalidLength() public {
        depositRequest.tokens = [address(dai), address(notion)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(depositRequest);
        // Trim the last 5 bytes from the array
        assembly {
            mstore(encoded, sub(mload(encoded), 5))
        }
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.decodeDepositRequest(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeDepositRequest_IncorrectMessageType() public {
        depositRequest.tokens = [address(dai), address(notion)];
        depositRequest.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        bytes memory encoded = Codec.encode(depositRequest);
        // Set message type to DepositResponse
        assembly {
            let dataPtr := add(encoded, 0x20)
            mstore8(dataPtr, 1)
        }
        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, 1));
        Codec.decodeDepositRequest(encoded);
    }

    function test_DecodeDepositResponse() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAH = 1_000 * NOTION_PRECISION;
        depositResponse.navAE = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(depositResponse);
        Codec.DepositResponse memory decoded = Codec.decodeDepositResponse(encoded);
        assertEq(
            decoded.tokens.length,
            depositResponse.tokens.length,
            "test_DecodeDepositResponse: decoded tokens length"
        );
        assertEq(
            decoded.amounts.length,
            depositResponse.amounts.length,
            "test_DecodeDepositResponse: decoded amounts length"
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeDepositResponse_InvalidLength() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAH = 1_000 * NOTION_PRECISION;
        depositResponse.navAE = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(depositResponse);
        // Trim the last 5 bytes from the array
        assembly {
            mstore(encoded, sub(mload(encoded), 5))
        }
        vm.expectRevert(Codec.InvalidDataLength.selector);
        Codec.decodeDepositResponse(encoded);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertIf_DecodeDepositResponse_IncorrectMessageType() public {
        depositResponse.tokens = [address(dai), address(notion)];
        depositResponse.amounts = [1_000_000 * DAI_PRECISION, 1_000_000 * NOTION_PRECISION];
        depositResponse.navAH = 1_000 * NOTION_PRECISION;
        depositResponse.navAE = 1_000_000 * NOTION_PRECISION;
        bytes memory encoded = Codec.encode(depositResponse);
        // Set message type to DepositRequest
        assembly {
            let dataPtr := add(encoded, 0x20)
            mstore8(dataPtr, DEPOSIT_REQUEST_TYPE)
        }
        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, DEPOSIT_REQUEST_TYPE));
        Codec.decodeDepositResponse(encoded);
    }
}
