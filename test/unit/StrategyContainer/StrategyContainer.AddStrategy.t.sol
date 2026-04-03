// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";

contract StrategyContainerAddStrategyTest is StrategyContainerBaseTest {
    function test_AddStrategies() public {
        (
            MockStrategyInterfaceBased strategy,
            address[] memory strategyInputTokens,
            address[] memory strategyOutputTokens
        ) = _createAndAddStrategyWithTokens(1, 1, true);
        assertEq(strategyContainer.getStrategies().length, 1, "test_AddStrategies: Strategies length mismatch");
        assertEq(strategyContainer.getStrategies()[0], address(strategy), "test_AddStrategies: Strategy mismatch");
        assertEq(strategyContainer.isStrategy(address(strategy)), true, "test_AddStrategies: Strategy not added");
        assertEq(strategy.getInputTokens(), strategyInputTokens, "test_AddStrategies: Strategy input tokens mismatch");
        assertEq(
            strategy.getOutputTokens(),
            strategyOutputTokens,
            "test_AddStrategies: Strategy output tokens mismatch"
        );

        (strategy, strategyInputTokens, strategyOutputTokens) = _createAndAddStrategyWithTokens(2, 2, false);
        assertEq(strategyContainer.getStrategies().length, 2, "test_AddStrategies: Strategies length mismatch");
        assertEq(strategyContainer.getStrategies()[1], address(strategy), "test_AddStrategies: Strategy mismatch");
        assertEq(strategyContainer.isStrategy(address(strategy)), true, "test_AddStrategies: Strategy not added");
        assertEq(strategy.getInputTokens(), strategyInputTokens, "test_AddStrategies: Strategy input tokens mismatch");
        assertEq(
            strategy.getOutputTokens(),
            strategyOutputTokens,
            "test_AddStrategies: Strategy output tokens mismatch"
        );
    }

    function test_RevertIf_MaxStrategiesReached() public {
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            _createAndAddStrategyWithTokens(1, 1, true);
        }

        address strategy = address(new MockStrategyInterfaceBased(address(strategyContainer)));
        address[] memory strategyInputTokens = _createTokensArray(address(notion));
        address[] memory strategyOutputTokens = _createTokensArray(address(notion));

        vm.expectRevert(IStrategyContainer.MaxStrategiesReached.selector);
        strategyContainer.addStrategy(strategy, strategyInputTokens, strategyOutputTokens);
    }

    function test_RevertIf_StrategyAlreadyExists() public {
        (
            MockStrategyInterfaceBased strategy,
            address[] memory strategyInputTokens,
            address[] memory strategyOutputTokens
        ) = _createAndAddStrategyWithTokens(1, 1, true);
        vm.expectRevert(IStrategyContainer.StrategyAlreadyExists.selector);
        strategyContainer.addStrategy(address(strategy), strategyInputTokens, strategyOutputTokens);
    }

    function test_RevertIf_InputTokensIsEmpty() public {
        address strategy = address(new MockStrategyInterfaceBased(address(strategyContainer)));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategyContainer.addStrategy(strategy, new address[](0), _createTokensArray(address(notion)));
    }

    function test_RevertIf_OutputTokensIsEmpty() public {
        address strategy = address(new MockStrategyInterfaceBased(address(strategyContainer)));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategyContainer.addStrategy(strategy, _createTokensArray(address(notion)), new address[](0));
    }

    function test_RevertIf_InputTokensIsNotWhitelisted() public {
        address strategy = address(new MockStrategyInterfaceBased(address(strategyContainer)));
        address[] memory inputTokens = _createRandomTokensArray(1);
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, inputTokens[0]));
        strategyContainer.addStrategy(address(strategy), inputTokens, _createTokensArray(address(notion)));
    }

    function test_RevertIf_OutputTokensIsNotWhitelisted() public {
        address strategy = address(new MockStrategyInterfaceBased(address(strategyContainer)));
        address[] memory outputTokens = _createRandomTokensArray(1);
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, outputTokens[0]));
        strategyContainer.addStrategy(address(strategy), _createTokensArray(address(notion)), outputTokens);
    }

    function test_RevertIf_StrategyIsZeroAddress() public {
        address[] memory strategyInputTokens = _createTokensArray(address(notion));
        address[] memory strategyOutputTokens = _createTokensArray(address(notion));
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.addStrategy(address(0), strategyInputTokens, strategyOutputTokens);
    }

    function test_AddStrategy_AfterStrategyIsRemoved() public {
        MockStrategy strategy = _deployMockStrategy(address(strategyContainer));
        address[] memory strategyInputTokens = _createTokensArray(address(notion));
        address[] memory strategyOutputTokens = _createTokensArray(address(notion));

        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        vm.startPrank(roles.reshufflingExecutor);
        strategyContainer.addStrategy(address(strategy), strategyInputTokens, strategyOutputTokens);
        strategyContainer.removeStrategy(address(strategy));
        strategyContainer.addStrategy(address(strategy), strategyInputTokens, strategyOutputTokens);
        vm.stopPrank();

        assertEq(
            strategyContainer.isStrategy(address(strategy)),
            true,
            "test_AddStrategy_AfterStrategyIsRemoved: Strategy not added"
        );
    }
}
