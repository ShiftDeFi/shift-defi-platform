// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerAgentBaseTest} from "./ContainerAgentBase.t.sol";

contract ContainerAgentEnterStrategyTest is ContainerAgentBaseTest {
    address internal strategy0;
    address internal strategy1;

    uint256[] internal inputAmounts = [DEPOSIT_AMOUNT];

    function setUp() public virtual override {
        super.setUp();
        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        strategy0 = _addStrategyNotionInputOutput();
        strategy1 = _addStrategyNotionInputOutput();

        vm.prank(roles.reshufflingExecutor);
        containerAgent.disableReshufflingMode();

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.BridgeClaimed);

        deal(address(notion), address(containerAgent), DEPOSIT_AMOUNT * 2);
    }

    function test_EnterStrategy() public {
        uint256 minNavDelta = 0;
        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy0, inputAmounts, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.BridgeClaimed),
            "test_EnterStrategy: Container status not BridgeClaimed"
        );

        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT,
            "test_EnterStrategy: Notion balance of containerAgent mismatch"
        );

        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy1, inputAmounts, minNavDelta);
        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered),
            "test_EnterStrategy: Container status not AllStrategiesEntered"
        );
    }

    function test_EnterStrategy_TheOnlyStrategy() public {
        /// @dev Make strategy0 the only strategy on container
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);

        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        containerAgent.removeStrategy(strategy1);

        vm.prank(roles.reshufflingExecutor);
        containerAgent.disableReshufflingMode();

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.BridgeClaimed);

        uint256 minNavDelta = 0;
        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy0, inputAmounts, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered),
            "test_EnterStrategy_TheOnlyStrategy: Container status not AllStrategiesEntered"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT,
            "test_EnterStrategy_TheOnlyStrategy: Notion balance of containerAgent mismatch"
        );
    }

    function test_RevertIf_EnterStrategy_IncorrectContainerStatus() public {
        uint256 minNavDelta = 0;

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy0, inputAmounts, minNavDelta);
    }

    function test_RevertIf_EnterStrategy_InReshufflingMode() public {
        uint256 minNavDelta = 0;

        _toggleReshufflingMode(true);

        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy0, inputAmounts, minNavDelta);
    }
}
