// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerAgentBaseTest} from "test/unit/ContainerAgent/ContainerAgentBase.t.sol";

contract ContainerAgentReshufflingGatewayTest is ContainerAgentBaseTest {
    function setUp() public override {
        super.setUp();

        vm.prank(roles.tokenManager);
        containerAgent.whitelistToken(address(dai));

        dai.mint(address(containerAgent), DEPOSIT_AMOUNT);
        notion.mint(address(containerAgent), DEPOSIT_AMOUNT);
    }

    function test_WithdrawToReshufflingGateway() public {
        _toggleReshufflingMode(true);

        uint256 tokenNumber = 2;
        address[] memory bridgeAdapters = new address[](tokenNumber);
        bridgeAdapters[0] = address(bridgeAdapter);
        bridgeAdapters[1] = address(bridgeAdapter);

        address[] memory tokens = new address[](tokenNumber);
        tokens[0] = address(dai);
        tokens[1] = address(notion);

        uint256[] memory amounts = new uint256[](tokenNumber);
        amounts[0] = DEPOSIT_AMOUNT;
        amounts[1] = DEPOSIT_AMOUNT;

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](tokenNumber);
        for (uint256 i = 0; i < tokenNumber; ++i) {
            instructions[i] = _craftBridgeInstruction(tokens[i], amounts[i]);
        }

        vm.prank(roles.reshufflingExecutor);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);

        assertEq(dai.balanceOf(address(containerAgent)), 0, "test_WithdrawToReshufflingGateway: dai balance not zero");
        assertEq(
            notion.balanceOf(address(containerAgent)),
            0,
            "test_WithdrawToReshufflingGateway: ContainerAgent notion balance not zero"
        );
        assertEq(
            dai.balanceOf(address(bridgeAdapter)),
            DEPOSIT_AMOUNT,
            "test_WithdrawToReshufflingGateway: BridgeAdapter dai balance mismatch"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            DEPOSIT_AMOUNT,
            "test_WithdrawToReshufflingGateway: BridgeAdapter notion balance mismatch"
        );
    }

    function test_RevertIf_WithdrawToReshufflingGateway_ArrayLengthMismatch() public {
        _toggleReshufflingMode(true);

        uint256 tokenNumber = 1;
        address[] memory bridgeAdapters = new address[](tokenNumber + 1);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](tokenNumber);
        instructions[0] = _craftBridgeInstruction(address(notion), DEPOSIT_AMOUNT);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_ZeroArrayLength() public {
        _toggleReshufflingMode(true);

        address[] memory bridgeAdapters = new address[](0);
        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](0);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_ReshufflingGatewayIsZeroAddress() public {
        _toggleReshufflingMode(true);

        uint256 tokenNumber = 1;
        address[] memory bridgeAdapters = new address[](tokenNumber);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](tokenNumber);
        instructions[0] = _craftBridgeInstruction(address(notion), DEPOSIT_AMOUNT);

        bytes32 reshufflingGatewaySlot = bytes32(uint256(19));
        vm.store(address(containerAgent), reshufflingGatewaySlot, bytes32(uint256(0)));

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_BridgeAdapterIsNotWhitelisted() public {
        _toggleReshufflingMode(true);

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(makeAddr("BRIDGE_ADAPTER"));

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = _craftBridgeInstruction(address(notion), DEPOSIT_AMOUNT);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_NotInReshufflingMode() public {
        uint256 tokenNumber = 1;
        address[] memory bridgeAdapters = new address[](tokenNumber);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](tokenNumber);
        instructions[0] = _craftBridgeInstruction(address(notion), DEPOSIT_AMOUNT);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ReshufflingModeDisabled.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_InEmergencyResolutionMode() public {
        _toggleEmergencyResolutionMode(true);

        uint256 tokenNumber = 1;
        address[] memory bridgeAdapters = new address[](tokenNumber);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](tokenNumber);
        instructions[0] = _craftBridgeInstruction(address(notion), DEPOSIT_AMOUNT);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        containerAgent.withdrawToReshufflingGateway(bridgeAdapters, instructions);
    }
}
