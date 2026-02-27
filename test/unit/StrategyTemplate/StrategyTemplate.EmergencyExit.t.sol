// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

contract StrategyTemplateEmergencyExitTest is StrategyTemplateBaseTest {
    uint256[] inputAmounts;

    function setUp() public override {
        super.setUp();

        bool stateOneIsTarget = false;
        bool stateOneIsProtocol = false;
        bool stateOneIsToken = true;
        uint8 stateOneHeight = 0;

        strategy.setState(ONE_STATE_ID, stateOneIsTarget, stateOneIsProtocol, stateOneIsToken, stateOneHeight);

        bool stateTwoIsTarget = false;
        bool stateTwoIsProtocol = true;
        bool stateTwoIsToken = false;
        uint8 stateTwoHeight = 1;

        strategy.setState(TWO_STATE_ID, stateTwoIsTarget, stateTwoIsProtocol, stateTwoIsToken, stateTwoHeight);

        bool stateThreeIsTarget = true;
        bool stateThreeIsProtocol = true;
        bool stateThreeIsToken = false;
        uint8 stateThreeHeight = 2;

        strategy.setState(
            THREE_STATE_ID,
            stateThreeIsTarget,
            stateThreeIsProtocol,
            stateThreeIsToken,
            stateThreeHeight
        );

        address[] memory inputTokens = new address[](1);
        address[] memory outputTokens = new address[](1);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);
        strategyContainer.addStrategy(address(strategy), inputTokens, outputTokens);
        vm.prank(address(strategyContainer));
        notion.approve(address(strategy), type(uint256).max);

        inputAmounts = _prepareEnterInputAmounts(address(strategy));

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);
    }

    function test_EmergencyExit_FullExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS);

        assertTrue(
            strategyContainer.isResolvingEmergency(),
            "test_EmergencyExit_FromTargetState: Emergency resolution not started on StrategyContainer"
        );
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_EmergencyExit_FromTargetState: Strategy NAV not unresolved on StrategyContainer"
        );
        assertTrue(
            strategy.isNavResolutionMode(),
            "test_EmergencyExit_FromTargetState: Nav resolution mode not activated on Strategy"
        );
    }

    function test_EmergencyExit_PartialExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS / 2);

        assertTrue(
            strategyContainer.isResolvingEmergency(),
            "test_EmergencyExit_FromTargetState: Emergency resolution not started on StrategyContainer"
        );
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_EmergencyExit_FromTargetState: Strategy NAV not unresolved on StrategyContainer"
        );
        assertTrue(
            strategy.isNavResolutionMode(),
            "test_EmergencyExit_FromTargetState: Nav resolution mode not activated on Strategy"
        );
    }

    function test_EmergencyExit_FullExit_Twice() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitFailed(toStateId);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS);
    }

    function test_RevertIf_EmergencyExit_ShareOutOfBounds() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.emergencyExit(TWO_STATE_ID, 0);

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.emergencyExit(TWO_STATE_ID, MAX_BPS + 1);
    }

    function test_RevertIf_EmergencyExit_StateNotFound() public {
        bytes32 toStateId = bytes32(uint256(100));
        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, toStateId));
        strategy.emergencyExit(toStateId, MAX_BPS);
    }

    function test_RevertIf_EmergencyExit_ToHigherState() public {
        bytes32 higherStateId = bytes32(uint256(111));
        strategy.setState(higherStateId, false, true, false, 111);
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectInput.selector);
        strategy.emergencyExit(higherStateId, MAX_BPS);
    }

    function test_RevertIf_TryEmergencyExit_NotCalledBySelf() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.Unauthorized.selector);
        strategy.tryEmergencyExit(TWO_STATE_ID, MAX_BPS);
    }

    function test_EmergencyExitMultiple() public {
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        bytes32[] memory toStateIds = new bytes32[](2);
        toStateIds[0] = TWO_STATE_ID;
        toStateIds[1] = ONE_STATE_ID;
        uint256[] memory shares = new uint256[](2);
        shares[0] = MAX_BPS;
        shares[1] = MAX_BPS;
        vm.prank(address(strategyContainer));
        strategy.emergencyExitMultiple(toStateIds, shares);

        assertTrue(
            strategyContainer.isResolvingEmergency(),
            "test_EmergencyExitMultiple: Emergency resolution not started on StrategyContainer"
        );
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_EmergencyExitMultiple: Strategy NAV not unresolved on StrategyContainer"
        );
        assertTrue(
            strategy.isNavResolutionMode(),
            "test_EmergencyExitMultiple: Nav resolution mode not activated on Strategy"
        );
    }

    function test_RevertIf_EmergencyExitMultiple_ArrayLengthMismatch() public {
        bytes32[] memory toStateIds = new bytes32[](2);
        toStateIds[0] = TWO_STATE_ID;
        toStateIds[1] = ONE_STATE_ID;
        uint256[] memory shares = new uint256[](1);
        shares[0] = MAX_BPS;
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        strategy.emergencyExitMultiple(toStateIds, shares);
    }

    function test_AcceptNav_FullExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS);

        vm.prank(address(roles.emergencyManager));
        strategy.acceptNav(toStateId);

        assertEq(
            strategy.currentStateId(),
            toStateId,
            "test_AcceptNav_FullExit: currentStateId not set to accepted state"
        );

        assertFalse(
            strategy.isNavResolutionMode(),
            "test_AcceptNav_FullExit: nav resolution mode not deactivated on Strategy"
        );

        assertFalse(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_AcceptNav_FullExit: strategy NAV not resolved on StrategyContainer"
        );
    }

    function test_AcceptNav_PartialExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS / 2);

        vm.prank(address(roles.emergencyManager));
        strategy.acceptNav(toStateId);

        assertEq(
            strategy.currentStateId(),
            toStateId,
            "test_AcceptNav_PartialExit: currentStateId not set to accepted state"
        );

        assertFalse(
            strategy.isNavResolutionMode(),
            "test_AcceptNav_PartialExit: nav resolution mode not deactivated on Strategy"
        );

        assertFalse(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_AcceptNav_PartialExit: strategy NAV not resolved on StrategyContainer"
        );
    }

    function test_RevertIf_AcceptNav_NavResolutionModeNotActivated() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(roles.emergencyManager));
        vm.expectRevert(IStrategyTemplate.NavResolutionModeNotActivated.selector);
        strategy.acceptNav(toStateId);
    }

    function test_RevertIf_AcceptNav_StateNotFound() public {
        bytes32 toStateId = TWO_STATE_ID;
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, MAX_BPS / 2);

        bytes32 notFoundStateId = bytes32(uint256(100));
        vm.prank(address(roles.emergencyManager));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, notFoundStateId));
        strategy.acceptNav(notFoundStateId);
    }
}
