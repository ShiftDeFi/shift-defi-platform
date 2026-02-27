// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ContainerLocalBaseTest} from "test/unit/ContainerLocal/ContainerLocalBase.t.sol";
import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

contract ContainerLocalStrategiesTest is ContainerLocalBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_EnterStrategyMultipleStatus() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        address[] memory strategies = new address[](0);
        uint256[][] memory inputAmounts = new uint256[][](0);
        uint256[] memory minNavDelta = new uint256[](0);

        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered),
            "test_EnterStrategyMultipleStatus: status mismatch"
        );
    }

    function test_RevertsIf_IncorrectContainerStatusAndEnterStrategyMultiple() public {
        address[] memory strategies = new address[](0);
        uint256[][] memory inputAmounts = new uint256[][](0);
        uint256[] memory minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    function test_RevertsIf_ArrayLengthMismatchAndEnterStrategyMultiple() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        address[] memory strategies = new address[](1);
        uint256[][] memory inputAmounts = new uint256[][](0);
        uint256[] memory minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](0);
        inputAmounts = new uint256[][](1);
        minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](0);
        inputAmounts = new uint256[][](0);
        minNavDelta = new uint256[](1);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](1);
        inputAmounts = new uint256[][](1);
        minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](0);
        inputAmounts = new uint256[][](1);
        minNavDelta = new uint256[](1);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](1);
        inputAmounts = new uint256[][](0);
        minNavDelta = new uint256[](1);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    function test_ExitStrategyMultipleStatus() public {
        uint256 amount = vault.minWithdrawBatchRatio();

        vm.prank(address(vault));
        containerLocal.registerWithdrawRequest(amount);

        address[] memory strategies = new address[](0);
        uint256[] memory maxNavDeltas = new uint256[](0);

        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesExited),
            "test_ExitStrategyMultipleStatus: status mismatch"
        );
    }

    function test_RevertsIf_IncorrectContainerStatusAndExitStrategyMultiple() public {
        address[] memory strategies = new address[](0);
        uint256[] memory maxNavDeltas = new uint256[](0);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_RevertsIf_ArrayLengthMismatchAndExitStrategyMultiple() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);

        address[] memory strategies = new address[](1);
        uint256[] memory maxNavDeltas = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);

        strategies = new address[](0);
        maxNavDeltas = new uint256[](1);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_RevertsIf_NoSharesRegisteredForExitAndExitStrategyMultiple() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);

        address[] memory strategies = new address[](0);
        uint256[] memory maxNavDeltas = new uint256[](0);

        vm.expectRevert(IStrategyContainer.NoSharesRegisteredForExit.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_AddStrategy() public {
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = address(notion);
        address[] memory outputTokens = new address[](1);
        outputTokens[0] = address(notion);

        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(address(strategy), inputTokens, outputTokens);

        assertEq(containerLocal.isStrategy(address(strategy)), true, "test_AddStrategy: strategy not added");
        assertEq(containerLocal.getStrategies().length, 1, "test_AddStrategy: strategies length mismatch");
        assertEq(containerLocal.getStrategies()[0], address(strategy), "test_AddStrategy: strategy address mismatch");
    }

    function test_RevertsIf_IncorrectContainerStatusAndAddStrategy() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        address[] memory inputTokens = new address[](0);
        address[] memory outputTokens = new address[](0);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(address(1), inputTokens, outputTokens);
    }

    function test_RemoveStrategy() public {
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = address(notion);
        address[] memory outputTokens = new address[](1);
        outputTokens[0] = address(notion);

        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(address(strategy), inputTokens, outputTokens);

        vm.prank(roles.strategyManager);
        containerLocal.removeStrategy(address(strategy));

        assertEq(containerLocal.isStrategy(address(strategy)), false, "test_RemoveStrategy: strategy not removed");
        assertEq(containerLocal.getStrategies().length, 0, "test_RemoveStrategy: strategies length mismatch");
    }

    function test_RevertsIf_IncorrectContainerStatusAndRemoveStrategy() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerLocal.removeStrategy(address(strategy));
    }

    function test_EnterStrategy() public {
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = address(notion);
        address[] memory outputTokens = new address[](1);
        outputTokens[0] = address(notion);

        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(address(strategy), inputTokens, outputTokens);

        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);
        deal(address(notion), address(containerLocal), 1);

        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = 1;
        uint256 minNavDelta = 0;

        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), inputAmounts, minNavDelta);
        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered),
            "test_EnterStrategy: status mismatch"
        );
    }

    function test_RevertsIf_IncorrectContainerStatusAndEnterStrategy() public {
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), new uint256[](0), 0);
    }
}
