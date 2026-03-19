// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

contract StrategyTemplateEmergencyExitTest is StrategyTemplateBaseTest {
    using Math for uint256;

    MockStrategy secondStrategy;
    uint256[] inputAmounts;
    uint256 constant EMERGENCY_EXIT_SLIPPAGE_TOLERANCE = 0.98e18; // 2%

    function setUp() public override {
        super.setUp();

        secondStrategy = _deployMockStrategy(address(strategyContainer));

        bool stateOneIsTarget = false;
        bool stateOneIsProtocol = false;
        bool stateOneIsToken = true;
        uint8 stateOneHeight = 0;

        strategy.setState(ONE_STATE_ID, stateOneIsTarget, stateOneIsProtocol, stateOneIsToken, stateOneHeight);
        secondStrategy.setState(ONE_STATE_ID, stateOneIsTarget, stateOneIsProtocol, stateOneIsToken, stateOneHeight);

        bool stateTwoIsTarget = false;
        bool stateTwoIsProtocol = true;
        bool stateTwoIsToken = false;
        uint8 stateTwoHeight = 1;

        strategy.setState(TWO_STATE_ID, stateTwoIsTarget, stateTwoIsProtocol, stateTwoIsToken, stateTwoHeight);
        secondStrategy.setState(TWO_STATE_ID, stateTwoIsTarget, stateTwoIsProtocol, stateTwoIsToken, stateTwoHeight);

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
        secondStrategy.setState(
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

        strategyContainer.addStrategy(address(secondStrategy), inputTokens, outputTokens);
        vm.prank(address(strategyContainer));
        notion.approve(address(secondStrategy), type(uint256).max);

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT * 2);
    }

    function test_EmergencyExit_FullExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        uint256 exitShare = MAX_BPS;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

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
        uint256 exitShare = MAX_BPS / 2;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

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
        uint256 exitShare = MAX_BPS;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitSucceeded(toStateId);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

        vm.expectEmit();
        emit IStrategyTemplate.EmergencyExitFailed(toStateId);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, 0);
    }

    function test_EmergencyExit_MultipleStrategies() public {
        bytes32 toStateId = TWO_STATE_ID;
        uint256 exitShare = MAX_BPS;
        uint256 bitmaskAfterFirstExit = 1 << 0;
        uint256 bitmaskAfterSecondExit = bitmaskAfterFirstExit | (1 << 1);

        vm.startPrank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);
        secondStrategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);
        vm.stopPrank();

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

        uint256 unresolvedNavBitmask = _getStrategyUnresolvedNavBitmask();
        assertEq(
            unresolvedNavBitmask,
            bitmaskAfterFirstExit,
            "test_EmergencyExit_MultipleStrategies: First strategy should be unresolved"
        );

        vm.prank(address(strategyContainer));
        secondStrategy.emergencyExit(toStateId, exitShare, minNavDelta);

        unresolvedNavBitmask = _getStrategyUnresolvedNavBitmask();
        assertEq(
            unresolvedNavBitmask,
            bitmaskAfterSecondExit,
            "test_EmergencyExit_MultipleStrategies: Second strategy should be unresolved"
        );
    }

    function test_RevertIf_EmergencyExit_ShareOutOfBounds() public {
        uint256 exitShare = 0;

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.emergencyExit(TWO_STATE_ID, exitShare, 0);

        exitShare = MAX_BPS + 1;

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.emergencyExit(TWO_STATE_ID, exitShare, 0);
    }

    function test_RevertIf_EmergencyExit_StateNotFound() public {
        bytes32 toStateId = bytes32(uint256(100));
        uint256 exitShare = MAX_BPS;

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, toStateId));
        strategy.emergencyExit(toStateId, exitShare, 0);
    }

    function test_RevertIf_EmergencyExit_AlreadyInState() public {
        uint256 exitShare = MAX_BPS;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        bytes32 toStateId = strategy.currentStateId();
        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.AlreadyInState.selector, toStateId));
        strategy.emergencyExit(toStateId, exitShare, 0);
    }

    function test_RevertIf_EmergencyExit_SlippageCheckFailed() public {
        bytes32 toStateId = TWO_STATE_ID;
        uint256 exitShare = MAX_BPS / 2;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 toStateNavBefore = strategy.stateNav(toStateId);
        uint256 expectedNavExit = strategy.currentStateNav().mulDiv(exitShare, MAX_BPS);
        uint256 slippageNavDelta = expectedNavExit + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyTemplate.SlippageCheckFailed.selector,
                toStateNavBefore,
                expectedNavExit,
                slippageNavDelta
            )
        );

        vm.prank(address(roles.emergencyManager));
        strategy.emergencyExit(toStateId, exitShare, slippageNavDelta);
    }

    function test_RevertIf_EmergencyExit_ToHigherState() public {
        bytes32 toStateId = bytes32(uint256(111));
        uint256 exitShare = MAX_BPS;

        strategy.setState(toStateId, false, true, false, 111);

        vm.prank(address(strategyContainer));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyTemplate.CannotExitToStateWithHigherHeight.selector,
                toStateId,
                NO_ALLOCATION_STATE_ID
            )
        );
        strategy.emergencyExit(toStateId, exitShare, 0);
    }

    function test_RevertIf_TryEmergencyExit_NotCalledBySelf() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.Unauthorized.selector);
        strategy.tryEmergencyExit(TWO_STATE_ID, MAX_BPS);
    }

    function test_AcceptNav_FullExit() public {
        bytes32 toStateId = TWO_STATE_ID;
        uint256 exitShare = MAX_BPS;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);

        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

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
        uint256 exitShare = MAX_BPS / 2;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

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
        uint256 exitShare = MAX_BPS / 2;

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 minNavDelta = _calculateEmergencyExitMinNavDelta(exitShare);
        vm.prank(address(strategyContainer));
        strategy.emergencyExit(toStateId, exitShare, minNavDelta);

        bytes32 notFoundStateId = bytes32(uint256(100));
        vm.prank(address(roles.emergencyManager));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, notFoundStateId));
        strategy.acceptNav(notFoundStateId);
    }

    function _calculateEmergencyExitMinNavDelta(uint256 share) internal view returns (uint256) {
        uint256 expectedExitAmount = strategy.currentStateNav().mulDiv(share, MAX_BPS);
        return expectedExitAmount.mulDiv(EMERGENCY_EXIT_SLIPPAGE_TOLERANCE, MAX_BPS);
    }
}
