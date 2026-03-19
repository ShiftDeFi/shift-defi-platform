// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {Codec} from "contracts/libraries/Codec.sol";

import {ContainerAgentBaseTest} from "test/unit/ContainerAgent/ContainerAgentBase.t.sol";

contract ContainerAgentReceiveMessageTest is ContainerAgentBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_ReceiveMessage_DepositRequest() public {
        uint256 tokenNumber = 1;
        address[] memory tokens = new address[](tokenNumber);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](tokenNumber);
        amounts[0] = DEPOSIT_AMOUNT;

        bytes memory rawMessage = _craftDepositRequestMessage(tokens, amounts);
        uint256 claimCounterBefore = containerAgent.claimCounter();

        vm.prank(address(messageRouter));
        containerAgent.receiveMessage(rawMessage);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.DepositRequestReceived),
            "test_ReceiveMessage_DepositRequest: status not DepositRequestReceived"
        );
        assertEq(
            containerAgent.claimCounter(),
            claimCounterBefore + tokenNumber,
            "test_ReceiveMessage_DepositRequest: claim counter not increased"
        );
    }

    function test_ReceiveMessage_WithdrawalRequest() public {
        uint256 share = 1_000; // 10%
        bytes memory rawMessage = _craftWithdrawalRequestMessage(share);

        vm.prank(address(messageRouter));
        containerAgent.receiveMessage(rawMessage);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived),
            "test_ReceiveMessage_WithdrawalRequest: status not WithdrawalRequestReceived"
        );
        assertEq(
            containerAgent.registeredWithdrawShareAmount(),
            share,
            "test_ReceiveMessage_WithdrawalRequest: registered withdraw share amount not updated"
        );
    }

    function test_RevertIf_ReceiveMessage_IncorrectContainerStatus() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);
        bytes memory withdrawalRequestMessage = _craftWithdrawalRequestMessage(1_000);
        vm.prank(address(messageRouter));
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerAgent.receiveMessage(withdrawalRequestMessage);
    }

    function test_RevertIf_ReceiveMessage_WrongMessageType() public {
        uint256 share = 1_000;
        bytes memory wrongMessage = _craftWithdrawalRequestMessage(share);
        wrongMessage[0] = bytes1(uint8(3)); // Change message type to WITHDRAW_RESPONSE
        vm.prank(address(messageRouter));
        vm.expectRevert(abi.encodeWithSelector(Codec.WrongMessageType.selector, uint8(wrongMessage[0])));
        containerAgent.receiveMessage(wrongMessage);
    }

    function test_RevertIf_ReceiveMessage_InReshufflingMode() public {
        _toggleReshufflingMode(true);
        uint256 share = 1_000;
        bytes memory rawMessage = _craftWithdrawalRequestMessage(share);
        vm.prank(address(messageRouter));
        vm.expectRevert(IStrategyContainer.ActionUnavailableInReshufflingMode.selector);
        containerAgent.receiveMessage(rawMessage);
    }

    function test_RevertIf_ReceiveMessage_InEmergencyResolutionMode() public {
        _toggleEmergencyResolutionMode(true);
        uint256 share = 1_000;
        bytes memory rawMessage = _craftWithdrawalRequestMessage(share);
        vm.prank(address(messageRouter));
        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        containerAgent.receiveMessage(rawMessage);
    }
}
