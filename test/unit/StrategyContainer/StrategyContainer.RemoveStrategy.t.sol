// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyContainerRemoveStrategyTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal strategy;
    MockStrategyInterfaceBased internal strategyWithRandomTokens;

    function setUp() public override {
        super.setUp();
        (strategy, , ) = _createAndAddStrategyWithTokens(1, 1, true);
        (strategyWithRandomTokens, , ) = _createAndAddStrategyWithTokens(2, 2, false);
    }

    function test_RemoveStrategy() public {
        vm.prank(roles.strategyManager);
        strategyContainer.removeStrategy(address(strategy));
        assertEq(strategyContainer.getStrategies().length, 1, "test_RemoveStrategy: Strategies length mismatch");
        assertEq(strategyContainer.isStrategy(address(strategy)), false, "test_RemoveStrategy: Strategy not removed");
        address[] memory inputTokens = strategy.getInputTokens();
        for (uint256 i = 0; i < inputTokens.length; i++) {
            assertEq(
                IERC20(inputTokens[i]).allowance(address(strategy), address(strategyContainer)),
                0,
                "test_RemoveStrategy: Input token allowance not removed"
            );
        }

        vm.prank(roles.strategyManager);
        strategyContainer.removeStrategy(address(strategyWithRandomTokens));
        assertEq(strategyContainer.getStrategies().length, 0, "test_RemoveStrategy: Strategies length mismatch");
        assertEq(
            strategyContainer.isStrategy(address(strategyWithRandomTokens)),
            false,
            "test_RemoveStrategy: Strategy not removed"
        );
        address[] memory inputTokens2 = strategyWithRandomTokens.getInputTokens();
        for (uint256 i = 0; i < inputTokens2.length; i++) {
            assertEq(
                IERC20(inputTokens2[i]).allowance(address(strategyWithRandomTokens), address(strategyContainer)),
                0,
                "test_RemoveStrategy: Input token allowance not removed"
            );
        }
    }

    function test_RevertIf_StrategyAddressIsZeroAddress() public {
        vm.prank(roles.strategyManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.removeStrategy(address(0));
    }

    function test_RevertIf_StrategyNotFound() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(roles.strategyManager);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.removeStrategy(randomAddress);
    }
}
