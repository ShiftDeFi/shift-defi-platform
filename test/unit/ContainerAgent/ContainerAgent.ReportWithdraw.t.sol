// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerAgentBaseTest} from "test/unit/ContainerAgent/ContainerAgentBase.t.sol";

contract ContainerAgentReportWithdrawTest is ContainerAgentBaseTest {
    function setUp() public override {
        super.setUp();

        notion.mint(address(containerAgent), WITHDRAWN_AMOUNT);
    }

    function test_ReportWithdraw() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = WITHDRAWN_AMOUNT;

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.Idle),
            "test_ReportWithdraw: status not idle"
        );
        uint256 strategyExitBitmask = _getStrategyExitBitmask();
        assertEq(strategyExitBitmask, 0, "test_ReportWithdraw: strategy exit bitmask not 0");
        assertEq(
            containerAgent.registeredWithdrawShareAmount(),
            0,
            "test_ReportWithdraw: registered withdraw share amount not 0"
        );

        assertEq(
            notion.balanceOf(address(containerAgent)),
            0,
            "test_ReportWithdraw: ContainerAgent notion balance not 0 after report withdrawal"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            WITHDRAWN_AMOUNT,
            "test_ReportWithdraw: BridgeAdapter notion balance not WITHDRAWN_AMOUNT after report withdrawal"
        );
    }

    function test_RevertIf_ReportWithdraw_StatusNotAllStrategiesExited() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_RemoteChainIdNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);
        _setRemoteChainId(0);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(ICrossChainContainer.RemoteChainIdNotSet.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_PeerContainerNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);
        _setPeerContainer(address(0));

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](1), new uint256[](1));

        vm.expectRevert(ICrossChainContainer.PeerContainerNotSet.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_BridgeAdaptersLengthMismatch() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);
        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = WITHDRAWN_AMOUNT;

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
        containerAgent.reportWithdrawal(messageInstruction, newBridgeAdapters, bridgeInstructions);

        IBridgeAdapter.BridgeInstruction[] memory newBridgeInstructions = new IBridgeAdapter.BridgeInstruction[](
            bridgeInstructions.length + 1
        );
        for (uint256 i = 0; i < newBridgeInstructions.length; ++i) {
            newBridgeInstructions[i] = bridgeInstructions[0];
        }

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, newBridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_MessageInstructionAdapterNotSet() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        messageInstruction.adapter = address(0);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_BridgeAdaptersLengthZero() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(new address[](0), new uint256[](0));

        vm.expectRevert(Errors.ZeroArrayLength.selector);
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_WhitelistedTokensOnBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);
        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = WITHDRAWN_AMOUNT;
        notion.mint(address(containerAgent), bridgedAmounts[0] + 1);

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        vm.expectRevert(abi.encodeWithSelector(IContainer.WhitelistedTokensOnBalance.selector, address(notion)));
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_MessageInstructionValueExceedsNativeBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = WITHDRAWN_AMOUNT;

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        messageInstruction.value = 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughNativeToken.selector, 1, 0));
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportWithdraw_BridgeInstructionValueExceedsNativeBalance() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.AllStrategiesExited);

        uint256 tokenNumber = 1;
        address[] memory bridgedTokens = new address[](tokenNumber);
        bridgedTokens[0] = address(notion);
        uint256[] memory bridgedAmounts = new uint256[](tokenNumber);
        bridgedAmounts[0] = WITHDRAWN_AMOUNT;

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareReportData(bridgedTokens, bridgedAmounts);

        bridgeInstructions[0].value = 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughNativeToken.selector, 1, 0));
        vm.prank(roles.operator);
        containerAgent.reportWithdrawal(messageInstruction, bridgeAdapters, bridgeInstructions);
    }
}
