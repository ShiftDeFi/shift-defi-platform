// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {ContainerAgentBaseTest} from "./ContainerAgentBase.t.sol";

contract ContainerAgentEnterStrategyTest is ContainerAgentBaseTest {
    address internal strategy0;
    address internal strategy1;

    uint256[] internal inputAmounts = [DEPOSIT_AMOUNT];

    function setUp() public virtual override {
        super.setUp();
        strategy0 = _addStrategyNotionInputOutput();
        strategy1 = _addStrategyNotionInputOutput();
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

        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy1);

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

        vm.expectRevert(IStrategyContainer.ActionUnavailableInReshufflingMode.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategy(strategy0, inputAmounts, minNavDelta);
    }

    function test_EnterStrategyMultiple_1Of1() public {
        /// @dev Make strategy0 the only strategy on container
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);

        vm.prank(roles.strategyManager);
        containerAgent.removeStrategy(strategy1);

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.BridgeClaimed);

        uint256 strategiesNumber = 1;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered),
            "test_EnterStrategyMultiple_1Of1: Container status not AllStrategiesEntered"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT * strategiesNumber,
            "test_EnterStrategyMultiple_1Of1: Notion balance of containerAgent mismatch"
        );
    }

    function test_EnterStrategyMultiple_1OfN() public {
        uint256 strategiesNumber = 1;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.BridgeClaimed),
            "test_EnterStrategyMultiple_1OfN: Container status not BridgeClaimed"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT * strategiesNumber,
            "test_EnterStrategyMultiple_1OfN: Notion balance of containerAgent mismatch"
        );
    }

    function test_EnterStrategyMultiple_MOfN() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);
        _addStrategyNotionInputOutput();
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.BridgeClaimed);

        uint256 strategiesNumber = 2;
        assertLt(
            strategiesNumber,
            containerAgent.getStrategies().length,
            "test_EnterStrategyMultiple_MOfN: Strategies number mismatch"
        );
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        inputAmountsMultiple[1] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        minNavDelta[1] = 0;

        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.BridgeClaimed),
            "test_EnterStrategyMultiple_MOfN: Container status not BridgeClaimed"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT * strategiesNumber,
            "test_EnterStrategyMultiple_NOfN: Notion balance of containerAgent mismatch"
        );
    }

    function test_EnterStrategyMultiple_NOfN() public {
        uint256 strategiesNumber = 2;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        inputAmountsMultiple[1] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        minNavDelta[1] = 0;

        uint256 containerBalanceBefore = notion.balanceOf(address(containerAgent));

        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesEntered),
            "test_EnterStrategyMultiple: Container status not AllStrategiesEntered"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            containerBalanceBefore - DEPOSIT_AMOUNT * strategiesNumber,
            "test_EnterStrategyMultiple_NOfN: Notion balance of containerAgent mismatch"
        );
    }

    function test_RevertIf_EnterStrategyMultiple_IncorrectContainerStatus() public {
        uint256 strategiesNumber = 2;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        minNavDelta[1] = 0;

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);
    }

    function test_RevertIf_EnterStrategyMultiple_InReshufflingMode() public {
        uint256 strategiesNumber = 2;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        minNavDelta[1] = 0;

        _toggleReshufflingMode(true);

        vm.expectRevert(IStrategyContainer.ActionUnavailableInReshufflingMode.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);
    }

    function test_RevertIf_EnterStrategyMultiple_ArrayLengthMismatch() public {
        uint256 strategiesNumber = 2;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        uint256[][] memory inputAmountsMultiple = new uint256[][](strategiesNumber - 1);
        inputAmountsMultiple[0] = inputAmounts;

        uint256[] memory minNavDelta = new uint256[](strategiesNumber - 1);
        minNavDelta[0] = 0;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);

        inputAmountsMultiple = new uint256[][](strategiesNumber);
        inputAmountsMultiple[0] = inputAmounts;
        inputAmountsMultiple[1] = inputAmounts;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerAgent.enterStrategyMultiple(strategies, inputAmountsMultiple, minNavDelta);
    }
}
