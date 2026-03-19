// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {StrategyStateLib} from "contracts/libraries/StrategyStateLib.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

contract StrategyTemplateStatesTest is StrategyTemplateBaseTest {
    uint8 internal constant STARTING_HEIGHT = 3;

    function setUp() public override {
        super.setUp();
    }

    function test_SetState_TokenState() public {
        bool isTargetState = false;
        bool isProtocolState = false;
        bool isTokenState = true;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);

        uint256 stateBitmask = _getStateBitmask(ONE_STATE_ID);

        assertEq(
            StrategyStateLib.isProtocolState(stateBitmask),
            isProtocolState,
            "test_setState_TokenState: isProtocolState"
        );
        assertEq(StrategyStateLib.isTokenState(stateBitmask), isTokenState, "test_setState_TokenState: isTokenState");
        assertEq(
            StrategyStateLib.isTargetState(stateBitmask),
            isTargetState,
            "test_setState_TokenState: isTargetState"
        );
        assertEq(StrategyStateLib.height(stateBitmask), STARTING_HEIGHT, "test_setState_TokenState: height");
        assertNotEq(_getTargetStateId(), ONE_STATE_ID, "test_setState_TokenState: targetStateId");
    }

    function test_SetState_ProtocolState() public {
        bool isTargetState = false;
        bool isProtocolState = true;
        bool isTokenState = false;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);

        uint256 stateBitmask = _getStateBitmask(ONE_STATE_ID);

        assertEq(
            StrategyStateLib.isProtocolState(stateBitmask),
            isProtocolState,
            "test_setState_ProtocolState: isProtocolState"
        );
        assertEq(
            StrategyStateLib.isTokenState(stateBitmask),
            isTokenState,
            "test_setState_ProtocolState: isTokenState"
        );
        assertEq(
            StrategyStateLib.isTargetState(stateBitmask),
            isTargetState,
            "test_setState_ProtocolState: isTargetState"
        );
        assertEq(StrategyStateLib.height(stateBitmask), STARTING_HEIGHT, "test_setState_ProtocolState: height");
        assertNotEq(_getTargetStateId(), ONE_STATE_ID, "test_setState_ProtocolState: targetStateId");
    }

    function test_SetState_TargetState() public {
        bool isTargetState = true;
        bool isProtocolState = true;
        bool isTokenState = false;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);

        uint256 stateBitmask = _getStateBitmask(ONE_STATE_ID);

        assertEq(
            StrategyStateLib.isProtocolState(stateBitmask),
            isProtocolState,
            "test_setState_TargetState: isProtocolState"
        );
        assertEq(StrategyStateLib.isTokenState(stateBitmask), isTokenState, "test_setState_TargetState: isTokenState");
        assertEq(
            StrategyStateLib.isTargetState(stateBitmask),
            isTargetState,
            "test_setState_TargetState: isTargetState"
        );
        assertEq(StrategyStateLib.height(stateBitmask), STARTING_HEIGHT, "test_setState_TargetState: height");
    }

    function test_RevertIf_setState_NoAllocationStateId() public {
        bool isTargetState = false;
        bool isProtocolState = false;
        bool isTokenState = false;

        vm.expectRevert(IStrategyTemplate.IncorrectStateId.selector);
        strategy.setState(NO_ALLOCATION_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);
    }

    function test_RevertIf_setState_TargetStateAlreadySet() public {
        bool isTargetState = true;
        bool isProtocolState = false;
        bool isTokenState = false;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);

        vm.expectRevert(IStrategyTemplate.TargetStateAlreadySet.selector);
        strategy.setState(TWO_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);
    }

    function test_RevertIf_setState_SameStateId() public {
        bool isTargetState = true;
        bool isProtocolState = false;
        bool isTokenState = false;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);

        isTargetState = false;
        isTokenState = true;

        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateAlreadyExists.selector, ONE_STATE_ID));
        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);
    }

    function test_RevertIf_setState_TargetAndTokenState() public {
        bool isTargetState = true;
        bool isProtocolState = false;
        bool isTokenState = true;

        vm.expectRevert(StrategyStateLib.InconsistentState.selector);
        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);
    }

    function test_RevertIf_setState_ZeroState() public {
        bool isTargetState = false;
        bool isProtocolState = false;
        bool isTokenState = false;

        vm.expectRevert(StrategyStateLib.ZeroState.selector);
        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, STARTING_HEIGHT);
    }
}
