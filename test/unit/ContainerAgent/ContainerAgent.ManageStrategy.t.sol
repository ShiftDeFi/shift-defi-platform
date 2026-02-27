// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {ContainerAgentBaseTest} from "./ContainerAgentBase.t.sol";

contract ContainerAgentManageStrategyTest is ContainerAgentBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_AddStrategy() public {
        address strategy = _addStrategyNotionInputOutput();

        assertEq(containerAgent.getStrategies().length, 1, "test_AddStrategy: Strategies length mismatch");
        assertEq(containerAgent.getStrategies()[0], strategy, "test_AddStrategy: Strategies mismatch");
        assertTrue(containerAgent.isStrategy(strategy), "test_AddStrategy: Strategy not found");
    }

    function test_AddStrategyInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        address strategy = _addStrategyNotionInputOutput();

        assertEq(
            containerAgent.getStrategies().length,
            1,
            "test_AddStrategyInReshufflingMode: Strategies length mismatch"
        );
        assertEq(containerAgent.getStrategies()[0], strategy, "test_AddStrategyInReshufflingMode: Strategies mismatch");
        assertTrue(containerAgent.isStrategy(strategy), "test_AddStrategyInReshufflingMode: Strategy not found");
    }

    function test_RevertIf_AddStrategy_IncorrectContainerStatus() public {
        address strategy = address(_deployMockStrategy());
        uint256 tokenNumber = 1;
        address[] memory inputTokens = new address[](tokenNumber);
        address[] memory outputTokens = new address[](tokenNumber);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerAgent.addStrategy(strategy, inputTokens, outputTokens);
    }

    function test_RevertIf_AddStrategy_ResolvingEmergency() public {
        address strategy = address(_deployMockStrategy());

        _toggleEmergencyResolutionMode(true);

        uint256 tokenNumber = 1;
        address[] memory inputTokens = new address[](tokenNumber);
        address[] memory outputTokens = new address[](tokenNumber);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);

        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        vm.prank(roles.strategyManager);
        containerAgent.addStrategy(strategy, inputTokens, outputTokens);
    }

    function test_RevertIf_AddStrategy_MaxStrategiesReached() public {
        uint256 tokenNumber = 1;
        address[] memory inputTokens = new address[](tokenNumber);
        address[] memory outputTokens = new address[](tokenNumber);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);

        /// @dev Ignore gas to reach maximum strategies
        vm.pauseGasMetering();
        for (uint256 i = 0; i < MAX_STRATEGIES; ++i) {
            address strategy = address(_deployMockStrategy());
            vm.prank(roles.strategyManager);
            containerAgent.addStrategy(strategy, inputTokens, outputTokens);
        }
        vm.resumeGasMetering();

        address exceedingStrategy = address(_deployMockStrategy());
        vm.expectRevert(IStrategyContainer.MaxStrategiesReached.selector);
        vm.prank(roles.strategyManager);
        containerAgent.addStrategy(exceedingStrategy, inputTokens, outputTokens);
    }

    function test_RemoveStrategy() public {
        address strategy = _addStrategyNotionInputOutput();
        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy);

        assertEq(containerAgent.getStrategies().length, 0, "test_RemoveStrategy: Strategies length mismatch");
        assertFalse(containerAgent.isStrategy(strategy), "test_RemoveStrategy: Strategy not found");
    }

    function test_RemoveStrategyInReshufflingMode() public {
        address strategy = _addStrategyNotionInputOutput();

        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy);

        assertEq(
            containerAgent.getStrategies().length,
            0,
            "test_RemoveStrategyInReshufflingMode: Strategies length mismatch"
        );
        assertFalse(containerAgent.isStrategy(strategy), "test_RemoveStrategyInReshufflingMode: Strategy not found");
    }

    function test_RevertIf_RemoveStrategy_IncorrectContainerStatus() public {
        address strategy = _addStrategyNotionInputOutput();

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy);
    }

    function test_RevertIf_RemoveStrategy_ResolvingEmergency() public {
        address strategy = _addStrategyNotionInputOutput();

        _toggleEmergencyResolutionMode(true);

        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy);
    }
}
