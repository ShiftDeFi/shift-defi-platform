// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerAgentBaseTest} from "./ContainerAgentBase.t.sol";

contract ContainerAgentExitStrategyTest is ContainerAgentBaseTest {
    using Math for uint256;

    uint256 internal sharesToWithdrawPercent = 0.05e18;
    uint256 internal expectedNotionBalance;
    address internal strategy0;
    address internal strategy1;
    address internal strategy2;
    uint256 internal maxNavDeltaPercent = 0.01e18;
    uint256 internal maxNavDelta;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        strategy0 = _addStrategyNotionInputOutput();
        strategy1 = _addStrategyNotionInputOutput();
        strategy2 = _addStrategyNotionInputOutput();

        vm.prank(roles.reshufflingExecutor);
        containerAgent.disableReshufflingMode();

        uint256 strategiesNumber = 3;
        address[] memory strategies = new address[](strategiesNumber);
        strategies[0] = strategy0;
        strategies[1] = strategy1;
        strategies[2] = strategy2;
        uint256[][] memory inputAmounts = new uint256[][](strategiesNumber);
        inputAmounts[0] = new uint256[](1);
        inputAmounts[0][0] = DEPOSIT_AMOUNT;
        inputAmounts[1] = new uint256[](1);
        inputAmounts[1][0] = DEPOSIT_AMOUNT;
        inputAmounts[2] = new uint256[](1);
        inputAmounts[2][0] = DEPOSIT_AMOUNT;
        uint256[] memory minNavDelta = new uint256[](strategiesNumber);
        minNavDelta[0] = 0;
        minNavDelta[1] = 0;
        minNavDelta[2] = 0;

        deal(address(notion), address(containerAgent), DEPOSIT_AMOUNT * strategiesNumber);

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.BridgeClaimed);
        vm.startPrank(roles.operator);
        containerAgent.enterStrategy(strategies[0], inputAmounts[0], minNavDelta[0]);
        containerAgent.enterStrategy(strategies[1], inputAmounts[1], minNavDelta[1]);
        containerAgent.enterStrategy(strategies[2], inputAmounts[2], minNavDelta[2]);
        vm.stopPrank();
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived);

        _setRegisteredWithdrawShareAmount(sharesToWithdrawPercent);

        expectedNotionBalance = DEPOSIT_AMOUNT.mulDiv(sharesToWithdrawPercent, MAX_BPS);
        maxNavDelta = expectedNotionBalance.mulDiv(MAX_BPS + maxNavDeltaPercent, MAX_BPS);
    }

    function test_ExitStrategy() public {
        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy0, maxNavDelta);

        assertEq(
            notion.balanceOf(address(containerAgent)),
            expectedNotionBalance,
            "test_ExitStrategy: Notion balance of containerAgent mismatch strategy0"
        );
        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived),
            "test_ExitStrategy: Container status not WithdrawalRequestReceived"
        );

        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy1, maxNavDelta);

        assertEq(
            notion.balanceOf(address(containerAgent)),
            expectedNotionBalance * 2,
            "test_ExitStrategy: Notion balance of containerAgent mismatch strategy1"
        );
        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived),
            "test_ExitStrategy: Container status not WithdrawalRequestReceived"
        );

        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy2, maxNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesExited),
            "test_ExitStrategy: Container status not AllStrategiesExited"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            expectedNotionBalance * 3,
            "test_ExitStrategy: Notion balance of containerAgent mismatch strategy2"
        );
    }

    function test_ExitStrategy_TheOnlyStrategy() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.Idle);

        vm.prank(roles.reshufflingManager);
        containerAgent.enableReshufflingMode();

        vm.startPrank(roles.reshufflingExecutor);
        containerAgent.removeStrategy(strategy1);
        containerAgent.removeStrategy(strategy2);
        containerAgent.disableReshufflingMode();
        vm.stopPrank();

        vm.prank(roles.operator);

        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived);

        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy0, maxNavDelta);

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.AllStrategiesExited),
            "exitStratetgy_TheOnlyStrategy: Container status not AllStrategiesExited"
        );
        assertEq(
            notion.balanceOf(address(containerAgent)),
            expectedNotionBalance,
            "exitStratetgy_TheOnlyStrategy: Notion balance of containerAgent mismatch strategy0"
        );
    }

    function test_RevertIf_ExitStrategy_IncorrectContainerStatus() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.DepositRequestReceived);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy0, maxNavDelta);
    }

    function test_RevertIf_ExitStrategy_InReshufflingMode() public {
        _toggleReshufflingMode(true);

        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy0, maxNavDelta);
    }

    function test_RevertIf_ExitStrategy_NoSharesRegisteredForExit() public {
        _setRegisteredWithdrawShareAmount(0);

        vm.expectRevert(IStrategyContainer.NoSharesRegisteredForExit.selector);
        vm.prank(roles.operator);
        containerAgent.exitStrategy(strategy0, maxNavDelta);
    }
}
