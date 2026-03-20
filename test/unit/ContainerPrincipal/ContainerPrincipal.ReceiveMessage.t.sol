// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";

import {Codec} from "contracts/libraries/Codec.sol";
import {FaultyCodec} from "test/mocks/FaultyCodec.sol";
import {Common} from "contracts/libraries/Common.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {ContainerPrincipalBaseTest} from "test/unit/ContainerPrincipal/ContainerPrincipalBase.t.sol";

contract ContainerPrincipalReceiveMessageTest is ContainerPrincipalBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_RevertIf_ReceivedMessageInWrongStatus() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);
        vm.expectRevert(IContainerPrincipal.NotExpectingAnyResponse.selector);
        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage("test");
    }

    function test_RevertIf_ReceivedEmptyMessage() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);
        vm.expectRevert(Codec.InvalidDataLength.selector);
        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage("");
    }

    function test_RevertIf_ReceivedMessageWithIncorrectMessageType() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        bytes memory message = "IncorrectMessageType";
        uint8 incorrectMessageType = uint8(message[0]);

        vm.expectRevert(abi.encodeWithSelector(Codec.IncorrectMessageType.selector, incorrectMessageType));
        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);
    }

    function test_RevertIf_ReceivedMessageWithWrongMessageType() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        bytes memory message = hex"0011223344";
        uint8 wrongMessageType = Codec.DEPOSIT_REQUEST_TYPE;

        vm.expectRevert(abi.encodeWithSelector(Codec.WrongMessageType.selector, wrongMessageType));
        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);
    }

    function test_ReceiveDepositResponseWithoutRemainder() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 nav0 = 0;
        uint256 nav1 = vault.minDepositBatchSize();

        bytes memory message = _craftDepositResponseMessageSingleToken(address(0), 0, nav0, nav1);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.DepositResponseReceived),
            "test_ReceiveDepositResponseWithoutRemainder: status mismatch"
        );
        assertEq(
            containerPrincipal.nav0(),
            Common.toUnifiedDecimalsUint8(address(notion), nav0),
            "test_ReceiveDepositResponseWithoutRemainder: nav0 not correct"
        );
        assertEq(
            containerPrincipal.nav1(),
            Common.toUnifiedDecimalsUint8(address(notion), nav1),
            "test_ReceiveDepositResponseWithoutRemainder: nav1 not correct"
        );
        assertEq(
            containerPrincipal.claimCounter(),
            0,
            "test_ReceiveDepositResponseWithoutRemainder: claim counter mismatch"
        );
    }

    function test_ReceiveDepositResponseWithSingleTokenRemainder() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 depositBatchSize = vault.minDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainder = depositBatchSize - nav1;

        bytes memory message = _craftDepositResponseMessageSingleToken(address(notion), remainder, nav0, nav1);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.DepositResponseReceived),
            "test_ReceiveDepositResponseWithSingleTokenRemainder: status mismatch"
        );
        assertEq(
            containerPrincipal.nav0(),
            Common.toUnifiedDecimalsUint8(address(notion), nav0),
            "test_ReceiveDepositResponseWithSingleTokenRemainder: nav0 not correct"
        );
        assertEq(
            containerPrincipal.nav1(),
            Common.toUnifiedDecimalsUint8(address(notion), nav1),
            "test_ReceiveDepositResponseWithSingleTokenRemainder: nav1 not correct"
        );
        assertEq(
            containerPrincipal.claimCounter(),
            1,
            "test_ReceiveDepositResponseWithSingleTokenRemainder: claim counter mismatch"
        );

        uint256 expectedTokenAmount = _getAddressUintMappingValue(
            address(containerPrincipal),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(notion)
        );
        assertEq(
            expectedTokenAmount,
            remainder,
            "test_ReceiveDepositResponseWithSingleTokenRemainder: expected token amount mismatch"
        );
    }

    function test_ReceiveDepositResponseWithMultipleTokenRemainders() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 depositBatchSize = vault.minDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainderDai = (depositBatchSize - nav1) / 2;
        uint256 remainderNotion = depositBatchSize - nav1 - remainderDai;

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = remainderDai;
        amounts[1] = remainderNotion;

        _whitelistToken(address(containerPrincipal), address(dai));

        bytes memory message = _craftDepositResponseMessageMultipleTokens(tokens, amounts, nav0, nav1);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.DepositResponseReceived),
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: status mismatch"
        );
        assertEq(
            containerPrincipal.nav0(),
            nav0,
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: nav0 not correct"
        );
        assertEq(
            containerPrincipal.nav1(),
            nav1,
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: nav1 not correct"
        );
        assertEq(
            containerPrincipal.claimCounter(),
            tokens.length,
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: claim counter mismatch"
        );

        uint256 expectedTokenAmountDai = _getAddressUintMappingValue(
            address(containerPrincipal),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(dai)
        );

        assertEq(
            expectedTokenAmountDai,
            remainderDai,
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: expected token amount dai mismatch"
        );

        uint256 expectedTokenAmountNotion = _getAddressUintMappingValue(
            address(containerPrincipal),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(notion)
        );

        assertEq(
            expectedTokenAmountNotion,
            remainderNotion,
            "test_ReceiveDepositResponseWithMultipleTokenRemainders: expected token amount notion mismatch"
        );
    }

    function test_RevertIf_RemainderTokenNotWhitelisted() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 depositBatchSize = vault.minDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainder = depositBatchSize - nav1;

        bytes memory message = _craftDepositResponseMessageSingleToken(address(dai), remainder, nav0, nav1);

        vm.prank(address(messageRouter));
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        containerPrincipal.receiveMessage(message);
    }

    function test_RevertIf_ZeroAmountRemainder() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 depositBatchSize = vault.minDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize;
        uint256 remainder = 0;

        bytes memory message = _craftDepositResponseMessageSingleToken(address(notion), remainder, nav0, nav1);

        vm.prank(address(messageRouter));
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerPrincipal.receiveMessage(message);
    }

    function test_DuplicatingTokenRemainder() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        uint256 depositBatchSize = vault.minDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 duplicatingRemainder = (depositBatchSize - nav1) / 2;

        address[] memory duplicatingTokens = new address[](2);
        duplicatingTokens[0] = address(notion);
        duplicatingTokens[1] = address(notion);

        uint256[] memory duplicatingAmounts = new uint256[](2);
        duplicatingAmounts[0] = Common.toUnifiedDecimalsUint8(address(notion), duplicatingRemainder);
        duplicatingAmounts[1] = Common.toUnifiedDecimalsUint8(address(notion), duplicatingRemainder);

        bytes memory message = FaultyCodec.encode(
            FaultyCodec.DepositResponse(
                duplicatingTokens,
                duplicatingAmounts,
                Common.toUnifiedDecimalsUint8(address(notion), nav0),
                Common.toUnifiedDecimalsUint8(address(notion), nav1)
            )
        );

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(containerPrincipal.claimCounter(), 1, "test_DuplicatingTokenRemainder: ClaimCounter not 1");
        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(notion)),
            duplicatingRemainder * 2,
            "test_DuplicatingTokenRemainder: ExpectedTokenAmounts not correct"
        );
    }

    function test_ReceiveWithdrawalResponseSingleToken() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        uint256 withdrawnBatchSize = vault.minDepositBatchSize();

        bytes memory message = _craftWithdrawalResponseMessageSingleToken(address(notion), withdrawnBatchSize);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalResponseReceived),
            "test_ReceiveWithdrawalResponseSingleToken: Status not WithdrawalResponseReceived"
        );
        assertEq(containerPrincipal.claimCounter(), 1, "test_ReceiveWithdrawalResponseSingleToken: ClaimCounter not 1");
        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(notion)),
            withdrawnBatchSize,
            "test_ReceiveWithdrawalResponseSingleToken: ExpectedTokenAmounts not correct"
        );
    }

    function test_ReceiveWithdrawalResponseMultipleTokens() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        uint256 withdrawnBatchSize = vault.minDepositBatchSize();
        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = withdrawnBatchSize / 2;
        amounts[1] = withdrawnBatchSize / 2;

        _whitelistToken(address(containerPrincipal), address(dai));
        bytes memory message = _craftWithdrawalResponseMessageMultipleTokens(tokens, amounts);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalResponseReceived),
            "test_ReceiveWithdrawalResponseMultipleTokens: Status not WithdrawalResponseReceived"
        );
        assertEq(
            containerPrincipal.claimCounter(),
            2,
            "test_ReceiveWithdrawalResponseMultipleTokens: ClaimCounter not 2"
        );
        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(notion)),
            withdrawnBatchSize / 2,
            "test_ReceiveWithdrawalResponseMultipleTokens: ExpectedTokenAmounts not correct"
        );
        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(dai)),
            withdrawnBatchSize / 2,
            "test_ReceiveWithdrawalResponseMultipleTokens: ExpectedTokenAmounts not correct"
        );
    }

    function test_RevertIf_WithdrawnNotWhitelistedToken() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        uint256 withdrawnBatchSize = vault.minDepositBatchSize();
        bytes memory message = _craftWithdrawalResponseMessageSingleToken(address(dai), withdrawnBatchSize);

        vm.prank(address(messageRouter));
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        containerPrincipal.receiveMessage(message);
    }

    function test_RevertIf_ZeroAmountWithdrawn() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        uint256 withdrawnAmount = 0;
        bytes memory message = _craftWithdrawalResponseMessageSingleToken(address(notion), withdrawnAmount);

        vm.prank(address(messageRouter));
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerPrincipal.receiveMessage(message);
    }

    function test_DuplicatingWithdrawnTokens() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        uint256 withdrawnAmount = vault.minDepositAmount();

        address[] memory duplicatingTokens = new address[](2);
        duplicatingTokens[0] = address(notion);
        duplicatingTokens[1] = address(notion);

        uint256[] memory duplicatingAmounts = new uint256[](2);
        duplicatingAmounts[0] = Common.toUnifiedDecimalsUint8(address(notion), withdrawnAmount);
        duplicatingAmounts[1] = Common.toUnifiedDecimalsUint8(address(notion), withdrawnAmount);
        bytes memory message = FaultyCodec.encode(
            FaultyCodec.WithdrawalResponse(duplicatingTokens, duplicatingAmounts)
        );

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        assertEq(containerPrincipal.claimCounter(), 1, "test_DuplicatingWithdrawnTokens: ClaimCounter not 1");
        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(notion)),
            withdrawnAmount * 2,
            "test_DuplicatingWithdrawnTokens: ExpectedTokenAmounts not correct"
        );
    }

    function test_RevertIf_ReceivedResponseOfOppositeType() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        bytes memory withdrawalResponseMessage = _craftWithdrawalResponseMessageSingleToken(
            address(notion),
            vault.minDepositAmount()
        );

        vm.prank(address(messageRouter));
        vm.expectRevert(IContainerPrincipal.NotExpectingWithdrawalResponse.selector);
        containerPrincipal.receiveMessage(withdrawalResponseMessage);

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        bytes memory depositResponseMessage = _craftDepositResponseMessageSingleToken(
            address(0),
            0,
            0,
            Common.toUnifiedDecimalsUint8(address(notion), vault.minDepositAmount())
        );
        vm.prank(address(messageRouter));
        vm.expectRevert(IContainerPrincipal.NotExpectingDepositResponse.selector);
        containerPrincipal.receiveMessage(depositResponseMessage);
    }
}
