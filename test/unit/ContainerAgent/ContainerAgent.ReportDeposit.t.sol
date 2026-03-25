// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerAgentBaseTest} from "test/unit/ContainerAgent/ContainerAgentBase.t.sol";

contract ContainerAgentReportDepositTest is ContainerAgentBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_ReportDeposit_NoRemainder() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        uint256 remainderAmount = 0;
        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.Idle),
            "test_ReportDeposit_NoRemainder: status not idle"
        );
        uint256 strategyEnterBitmask = _getStrategyEnterBitmask();
        assertEq(strategyEnterBitmask, 0, "test_ReportDeposit_NoRemainder: strategy enter bitmask not 0");
        assertEq(
            notion.balanceOf(address(containerAgent)),
            remainderAmount,
            "test_ReportDeposit_NoRemainder: ContainerAgent notion balance not 0 after report deposit"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            remainderAmount,
            "test_ReportDeposit_NoRemainder: BridgeAdapter notion balance not 0 after report deposit"
        );
    }

    function test_ReportDeposit_WithNotionRemainder() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = DEPOSIT_AMOUNT / 2;
        notion.mint(address(containerAgent), bridgedAmounts[0]);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.Idle),
            "test_ReportDeposit_WithNotionRemainder: status not idle"
        );
        uint256 strategyEnterBitmask = _getStrategyEnterBitmask();
        assertEq(strategyEnterBitmask, 0, "test_ReportDeposit_WithNotionRemainder: strategy enter bitmask not 0");
        assertEq(
            containerAgent.registeredWithdrawShareAmount(),
            0,
            "test_ReportDeposit_WithNotionRemainder: registered withdraw share amount not 0 after report deposit"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            0,
            "test_ReportDeposit_WithNotionRemainder: ContainerAgent notion balance not 0 after report deposit"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            bridgedAmounts[0],
            "test_ReportDeposit_WithNotionRemainder: BridgeAdapter notion balance not bridgedAmounts[0] after report deposit"
        );
    }

    function test_RevertIf_ReportDeposit_IncorrectContainerStatus() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_RemoteChainIdNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        _setRemoteChainId(0);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(ICrossChainContainer.RemoteChainIdNotSet.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_PeerContainerNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        _setPeerContainer(address(0));

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(ICrossChainContainer.PeerContainerNotSet.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_BridgeAdaptersLengthMismatch() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = DEPOSIT_AMOUNT / 2;

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        address[] memory newBridgeAdapters = new address[](bridgeAdapters.length + 1);
        for (uint256 i = 0; i < newBridgeAdapters.length; ++i) {
            newBridgeAdapters[i] = bridgeAdapters[0];
        }

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, newBridgeAdapters, bridgeInstructions);

        IBridgeAdapter.BridgeInstruction[] memory newBridgeInstructions = new IBridgeAdapter.BridgeInstruction[](
            bridgeInstructions.length + 1
        );
        for (uint256 i = 0; i < newBridgeInstructions.length; ++i) {
            newBridgeInstructions[i] = bridgeInstructions[0];
        }

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, newBridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_MessageInstructionAdapterNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        messageInstruction.adapter = address(0);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_WhitelistedTokensOnBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = DEPOSIT_AMOUNT / 2;
        notion.mint(address(containerAgent), bridgedAmounts[0] + 1);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        vm.expectRevert(abi.encodeWithSelector(IContainer.WhitelistedTokensOnBalance.selector, address(notion)));
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_MessageInstructionValueExceedsNativeBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        messageInstruction.value = 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughNativeToken.selector, 1, 0));
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_BridgeInstructionValueExceedsNativeBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = DEPOSIT_AMOUNT / 2;
        notion.mint(address(containerAgent), bridgedAmounts[0]);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        bridgeInstructions[0].value = 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughNativeToken.selector, 1, 0));
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_ReportDeposit_MessageInstructionValue_WithPrefundedNativeBalanceAndZeroMsgValue() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        messageInstruction.value = 1;

        (bool success, ) = payable(address(containerAgent)).call{value: 1}("");
        assertTrue(success, "test_ReportDeposit_MessageInstructionValue: prefund failed");

        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_ReportDeposit_BridgeInstructionValue_WithPrefundedNativeBalanceAndZeroMsgValue() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = DEPOSIT_AMOUNT / 2;
        notion.mint(address(containerAgent), bridgedAmounts[0]);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        bridgeInstructions[0].value = 1;

        (bool success, ) = payable(address(containerAgent)).call{value: 1}("");
        assertTrue(success, "test_ReportDeposit_BridgeInstructionValue: prefund failed");

        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_InReshufflingMode() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        _toggleReshufflingMode(true);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_EmergencyResolutionInProgress() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered);
        _toggleEmergencyResolutionMode(true);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        vm.prank(roles.operator);
        containerAgent.reportDeposit(messageInstruction, bridgeAdapters, bridgeInstructions);
    }
}
