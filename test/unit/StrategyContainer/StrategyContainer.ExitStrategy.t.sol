// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

contract StrategyContainerExitStrategyTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal strategy;
    uint256 internal constant INPUT_TOKEN_COUNT = 2;
    uint256 internal constant OUTPUT_TOKEN_COUNT = 2;

    function setUp() public override {
        super.setUp();
        address[] memory outputTokens = new address[](OUTPUT_TOKEN_COUNT);
        (strategy, , outputTokens) = _createAndAddStrategyWithTokens(INPUT_TOKEN_COUNT, OUTPUT_TOKEN_COUNT, false);
    }

    function test_RevertIf_NotStrategy() public {
        vm.prank(roles.operator);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.exitStrategy(makeAddr("RANDOM_ADDRESS"), MAX_BPS, 0);
    }

    function test_RevertIf_StrategyNavUnresolved() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IStrategyContainer.StrategyNavUnresolved.selector, address(strategy)));
        strategyContainer.exitStrategy(address(strategy), MAX_BPS, 0);
    }

    function test_RevertIf_StrategyAlreadyExited() public {
        uint256 share = vm.randomUint(1, MAX_BPS);
        vm.prank(roles.operator);
        strategyContainer.exitStrategy(address(strategy), share, 0);
        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IStrategyContainer.StrategyAlreadyExited.selector, address(strategy)));
        strategyContainer.exitStrategy(address(strategy), share, 0);
    }

    function test_ExitStrategy_WithFullShare() public {
        address[] memory outputTokens = strategy.getOutputTokens();
        for (uint256 i = 0; i < outputTokens.length; i++) {
            uint256 amount = vm.randomUint(1e18, 1000e18);
            MockERC20(outputTokens[i]).mint(address(strategy), amount);
            strategy.approveToken(outputTokens[i], amount, address(strategyContainer));
        }

        vm.prank(roles.operator);
        strategyContainer.exitStrategy(address(strategy), MAX_BPS, 0);

        assertTrue(
            strategyContainer.validateExitStrategy(address(strategy)),
            "test_ExitStrategy_WithFullShare: Strategy not exited"
        );
    }

    function test_RevertIf_ArrayLengthMismatch() public {
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(MockStrategyInterfaceBased.exit.selector),
            abi.encode(new address[](1), new uint256[](2))
        );
        vm.prank(roles.operator);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        strategyContainer.exitStrategy(address(strategy), MAX_BPS, 0);
    }

    function test_ExitStrategy_WithPartialShare() public {
        address[] memory outputTokens = strategy.getOutputTokens();
        for (uint256 i = 0; i < outputTokens.length; i++) {
            uint256 amount = vm.randomUint(1e18, 1000e18);
            MockERC20(outputTokens[i]).mint(address(strategy), amount);
            strategy.approveToken(outputTokens[i], amount, address(strategyContainer));
        }

        uint256 share = MAX_BPS / 2;
        vm.prank(roles.operator);
        strategyContainer.exitStrategy(address(strategy), share, 0);

        assertTrue(
            strategyContainer.validateExitStrategy(address(strategy)),
            "test_ExitStrategy_WithPartialShare: Strategy not exited"
        );
    }
}
