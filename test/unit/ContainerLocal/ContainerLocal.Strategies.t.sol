// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerLocalBaseTest} from "test/unit/ContainerLocal/ContainerLocalBase.t.sol";

contract ContainerLocalStrategiesTest is ContainerLocalBaseTest {
    function setUp() public override {
        super.setUp();
        deal(address(notion), address(containerLocal), DEPOSIT_AMOUNT);
    }

    function test_EnterStrategyMultiple() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = address(strategy);
        uint256[][] memory inputAmounts = new uint256[][](strategiesNumber);
        inputAmounts[0] = new uint256[](strategiesNumber);
        inputAmounts[0][0] = DEPOSIT_AMOUNT;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;

        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered),
            "test_EnterStrategyMultiple: status mismatch"
        );
    }

    function test_RevertIf_EnterStrategyMultiple_IncorrectContainerStatus() public {
        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = address(strategy);
        uint256[][] memory inputAmounts = new uint256[][](strategiesNumber);
        inputAmounts[0] = new uint256[](strategiesNumber);
        inputAmounts[0][0] = DEPOSIT_AMOUNT;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    function test_RevertIf_EnterStrategyMultiple_InvalidArrayLength() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);
        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](0);
        uint256[][] memory inputAmounts = new uint256[][](strategiesNumber);
        inputAmounts[0] = new uint256[](strategiesNumber);
        inputAmounts[0][0] = DEPOSIT_AMOUNT;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        strategies = new address[](strategiesNumber + 1);
        strategies[0] = address(strategy);

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    function test_RevertIf_EnterStrategyMultiple_ArrayLengthMismatch() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        address[] memory strategies = new address[](1);
        uint256[][] memory inputAmounts = new uint256[][](0);
        uint256[] memory minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        minNavDelta = new uint256[](1);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);

        inputAmounts = new uint256[][](1);
        minNavDelta = new uint256[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    function test_ExitStrategyMultiple() public {
        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        uint256[] memory inputAmounts = new uint256[](strategiesNumber);
        inputAmounts[0] = DEPOSIT_AMOUNT;
        uint256 minNavDelta = 0;

        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), inputAmounts, minNavDelta);

        _setContainerStatus(IContainerLocal.ContainerLocalStatus.Idle);

        uint256 amount = vault.minWithdrawBatchRatio();

        vm.prank(address(vault));
        containerLocal.registerWithdrawRequest(amount);

        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = address(strategy);
        uint256[] memory maxNavDeltas = new uint256[](strategiesNumber);
        maxNavDeltas[0] = DEPOSIT_AMOUNT;

        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesExited),
            "test_ExitStrategyMultiple: status mismatch"
        );
    }

    function test_RevertIf_ExitStrategyMultiple_IncorrectContainerStatus() public {
        address[] memory strategies = new address[](0);
        uint256[] memory maxNavDeltas = new uint256[](0);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_RevertIf_ExitStrategyMultiple_InvalidArrayLength() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);
        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](0);
        uint256[] memory maxNavDeltas = new uint256[](strategiesNumber);
        maxNavDeltas[0] = DEPOSIT_AMOUNT;

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);

        strategies = new address[](strategiesNumber + 1);
        strategies[0] = address(strategy);

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_RevertIf_ExitStrategyMultiple_ArrayLengthMismatch() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);

        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = address(strategy);
        uint256[] memory maxNavDeltas = new uint256[](strategiesNumber + 1);
        maxNavDeltas[0] = DEPOSIT_AMOUNT;
        maxNavDeltas[1] = DEPOSIT_AMOUNT;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_RevertIf_ExitStrategyMultiple_NoSharesRegisteredForExit() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);

        uint256 strategiesNumber = containerLocal.getStrategiesNumber();
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = address(strategy);
        uint256[] memory maxNavDeltas = new uint256[](strategiesNumber);
        maxNavDeltas[0] = DEPOSIT_AMOUNT;

        vm.expectRevert(IStrategyContainer.NoSharesRegisteredForExit.selector);
        vm.prank(roles.operator);
        containerLocal.exitStrategyMultiple(strategies, maxNavDeltas);
    }

    function test_AddStrategy() public {
        IStrategyTemplate _strategy = _deployMockStrategy(address(containerLocal));

        uint256 strategiesNumberBefore = containerLocal.getStrategiesNumber();

        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(
            address(_strategy),
            _createTokensArray(address(notion)),
            _createTokensArray(address(notion))
        );

        assertEq(containerLocal.isStrategy(address(_strategy)), true, "test_AddStrategy: strategy not added");
        assertEq(
            containerLocal.getStrategiesNumber(),
            strategiesNumberBefore + 1,
            "test_AddStrategy: strategies number mismatch"
        );
    }

    function test_RevertIf_AddStrategy_IncorrectContainerStatus() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        IStrategyTemplate _strategy = _deployMockStrategy(address(containerLocal));

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerLocal.addStrategy(
            address(_strategy),
            _createTokensArray(address(notion)),
            _createTokensArray(address(notion))
        );
    }

    function test_RemoveStrategy() public {
        uint256 strategiesNumberBefore = containerLocal.getStrategiesNumber();

        vm.prank(roles.strategyManager);
        containerLocal.removeStrategy(address(strategy));

        assertEq(containerLocal.isStrategy(address(strategy)), false, "test_RemoveStrategy: strategy not removed");
        assertEq(
            containerLocal.getStrategiesNumber(),
            strategiesNumberBefore - 1,
            "test_RemoveStrategy: strategies number mismatch"
        );
    }

    function test_RevertIf_RemoveStrategy_IncorrectContainerStatus() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.strategyManager);
        containerLocal.removeStrategy(address(strategy));
    }

    function test_EnterStrategy() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = DEPOSIT_AMOUNT;
        uint256 minNavDelta = 0;

        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), inputAmounts, minNavDelta);
        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered),
            "test_EnterStrategy: status mismatch"
        );
    }

    function test_RevertIf_EnterStrategy_IncorrectContainerStatus() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.Idle);

        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = DEPOSIT_AMOUNT;
        uint256 minNavDelta = 0;

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), inputAmounts, minNavDelta);
    }
}
