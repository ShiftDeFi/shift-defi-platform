// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

contract StrategyTemplateEnterTest is StrategyTemplateBaseTest {
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
    }

    function test_EnterToState_TokenState() public {
        bytes32 toStateId = ONE_STATE_ID;

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
        assertEq(strategy.currentStateId(), toStateId, "test_EnterToState_TokenState: currentStateId not 1");
        assertEq(
            notion.balanceOf(address(strategyContainer)),
            0,
            "test_EnterToState_TokenState: strategyContainer notion balance should be 0 after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            DEPOSIT_AMOUNT,
            "test_EnterToState_TokenState: strategy notion balance should equal deposit after enter"
        );
    }

    function test_EnterToState_ProtocolState() public {
        bytes32 toStateId = TWO_STATE_ID;

        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);

        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
        assertEq(strategy.currentStateId(), toStateId, "test_EnterToState_ProtocolState: currentStateId not 1");
        assertEq(
            notion.balanceOf(address(strategy)),
            0,
            "test_EnterToState_ProtocolState: strategy notion balance should be 0 after enter to protocol state"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT,
            "test_EnterToState_ProtocolState: mockBuildingBlock notion balance should equal deposit after enter"
        );
    }

    function test_EnterToState_TargetState() public {
        bytes32 toStateId = THREE_STATE_ID;

        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);

        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
        assertEq(strategy.currentStateId(), toStateId, "test_EnterToState_TargetState: currentStateId not 1");
        assertEq(
            notion.balanceOf(address(strategy)),
            0,
            "test_EnterToState_TargetState: strategy notion balance should be 0 after enter to target state"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT,
            "test_EnterToState_TargetState: mockBuildingBlock notion balance should equal deposit after enter"
        );
    }

    function test_RevertIf_EnterToState_NoAllocationStateId() public {
        bytes32 toStateId = NO_ALLOCATION_STATE_ID;

        vm.expectRevert(Errors.IncorrectInput.selector);
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
    }

    function test_RevertIf_EnterToState_StateNotFound() public {
        bytes32 toStateId = bytes32(uint256(100));

        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.StateNotFound.selector, toStateId));
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
    }

    function test_RevertIf_EnterToState_InconsistentHeight() public {
        bytes32 toStateId = TWO_STATE_ID;

        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);

        toStateId = ONE_STATE_ID;
        vm.expectRevert(Errors.IncorrectInput.selector);
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
    }

    function test_RevertIf_EnterToState_SlippageCheckFailed() public {
        bytes32 toStateId = strategy.MOCK_SLIPPAGE_STATE_ID();

        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyTemplate.SlippageCheckFailed.selector,
                0,
                DEPOSIT_AMOUNT - strategy.MOCK_SLIPPAGE_AMOUNT(),
                ENTER_MIN_NAV_DELTA
            )
        );
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);
    }

    function test_Enter_FromNoAllocationState() public {
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        assertEq(
            strategy.currentStateId(),
            THREE_STATE_ID,
            "test_Enter_FromNoAllocationState: currentStateId not target state"
        );
        assertEq(
            notion.balanceOf(address(strategyContainer)),
            0,
            "test_Enter_FromNoAllocationState: strategyContainer notion balance should be 0 after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            0,
            "test_Enter_FromNoAllocationState: strategy notion balance should be 0 after enter to target"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT,
            "test_Enter_FromNoAllocationState: mockBuildingBlock should hold deposit after enter"
        );
    }

    function test_Enter_FromTargetState() public {
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        assertEq(
            strategy.currentStateId(),
            THREE_STATE_ID,
            "test_Enter_FromTargetState: currentStateId not target state"
        );
        assertEq(
            notion.balanceOf(address(strategyContainer)),
            0,
            "test_Enter_FromTargetState: strategyContainer notion balance should be 0 after second enter"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT * 2,
            "test_Enter_FromTargetState: mockBuildingBlock should hold both deposits after two enters"
        );
    }

    function test_Enter_FromInterimState() public {
        // Enter interim state
        bytes32 toStateId = TWO_STATE_ID;
        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);
        _enterToState(toStateId, ENTER_MIN_NAV_DELTA);

        // Enter at interim state
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));
        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        assertEq(strategy.currentStateId(), toStateId, "test_Enter_FromInterimState: currentStateId not interim state");
        assertEq(
            notion.balanceOf(address(strategyContainer)),
            0,
            "test_Enter_FromInterimState: strategyContainer notion balance should be 0 after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            0,
            "test_Enter_FromInterimState: strategy notion balance should be 0 after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT * 2,
            "test_Enter_FromInterimState: mockBuildingBlock should hold both deposits"
        );
    }

    function test_RevertIf_Enter_NavResolutionModeActive() public {
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));

        _toggleNavResolutionMode(true);

        vm.expectRevert(IStrategyTemplate.NavResolutionModeActivated.selector);
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);
    }

    function test_RevertIf_Enter_SlippageCheckFailed() public {
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyTemplate.SlippageCheckFailed.selector,
                0,
                DEPOSIT_AMOUNT,
                ENTER_MIN_NAV_DELTA + 1
            )
        );
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA + 1);
    }

    function test_Enter_WithRemainder() public {
        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));

        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        _setTargetStateId(strategy.MOCK_REMAINDER_STATE_ID());
        uint256 remainderAmount = strategy.MOCK_REMAINDER_AMOUNT();
        vm.prank(address(strategyContainer));
        (uint256 stateToNavAfterEnter, bool hasRemainder, uint256[] memory remainingAmounts) = strategy.enter(
            inputAmounts,
            ENTER_MIN_NAV_DELTA - remainderAmount
        );

        assertEq(hasRemainder, true, "test_Enter_WithRemainder: hasRemainder not true");
        assertEq(remainingAmounts.length, 1, "test_Enter_WithRemainder: remainingAmounts length not 1");
        assertEq(
            remainingAmounts[0],
            remainderAmount,
            "test_Enter_WithRemainder: remainingAmounts not remainder amount"
        );
        assertEq(
            stateToNavAfterEnter,
            DEPOSIT_AMOUNT - remainderAmount,
            "test_Enter_WithRemainder: stateToNavAfterEnter not correct"
        );
        assertEq(
            notion.balanceOf(address(strategyContainer)),
            0,
            "test_Enter_WithRemainder: strategyContainer notion balance should be 0 after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            remainderAmount,
            "test_Enter_WithRemainder: strategy should hold remainder amount after enter"
        );
        assertEq(
            notion.balanceOf(address(strategy.mockBuildingBlock())),
            DEPOSIT_AMOUNT - remainderAmount,
            "test_Enter_WithRemainder: mockBuildingBlock should hold deposit minus remainder"
        );
    }
}
