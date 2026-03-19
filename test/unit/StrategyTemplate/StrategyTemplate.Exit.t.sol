// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

import {console2 as console} from "forge-std/console2.sol";

contract StrategyTemplateExitTest is StrategyTemplateBaseTest {
    using Math for uint256;

    uint256[] inputAmounts;

    function setUp() public override {
        super.setUp();

        bool stateOneIsTarget = false;
        bool stateOneIsProtocol = false;
        bool stateOneIsToken = true;
        uint8 stateOneHeight = 1;

        strategy.setState(ONE_STATE_ID, stateOneIsTarget, stateOneIsProtocol, stateOneIsToken, stateOneHeight);

        bool stateTwoIsTarget = false;
        bool stateTwoIsProtocol = true;
        bool stateTwoIsToken = false;
        uint8 stateTwoHeight = 2;

        strategy.setState(TWO_STATE_ID, stateTwoIsTarget, stateTwoIsProtocol, stateTwoIsToken, stateTwoHeight);

        bool stateThreeIsTarget = true;
        bool stateThreeIsProtocol = true;
        bool stateThreeIsToken = false;
        uint8 stateThreeHeight = 3;

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

    function test_Exit_FromTargetState_PartialExit() public {
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS / 2;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            THREE_STATE_ID,
            "test_Exit_FromTargetState_PartialExit: state after exit changed"
        );
        assertEq(
            strategy.stateNav(TWO_STATE_ID),
            DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromTargetState_PartialExit: strategy notion balance should equal exited share from target"
        );
        assertEq(
            notion.balanceOf(address(strategy.stateToBuildingBlock(THREE_STATE_ID))),
            DEPOSIT_AMOUNT - DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromTargetState_PartialExit: mockBuildingBlock should hold remaining after partial exit"
        );
    }

    function test_Exit_FromTargetState_FullExit() public {
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            NO_ALLOCATION_STATE_ID,
            "test_Exit_FromTargetState_FullExit: state after full exit not no allocation state"
        );
        assertEq(
            strategy.stateNav(TWO_STATE_ID),
            DEPOSIT_AMOUNT,
            "test_Exit_FromTargetState_FullExit: strategy notion balance should equal full deposit after exit"
        );
        assertEq(
            notion.balanceOf(address(strategy.stateToBuildingBlock(THREE_STATE_ID))),
            0,
            "test_Exit_FromTargetState_FullExit: mockBuildingBlock notion balance should be 0 after full exit"
        );
    }

    function test_Exit_FromTokenState_PartialExit() public {
        _enterToState(ONE_STATE_ID, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS / 2;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            ONE_STATE_ID,
            "test_Exit_FromTokenState_PartialExit: state after exit changed"
        );
        assertEq(
            notion.allowance(address(strategy), address(strategyContainer)),
            DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromTokenState_PartialExit: incorrect token out allowance to strategy container"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            DEPOSIT_AMOUNT,
            "test_Exit_FromTokenState_PartialExit: strategy notion balance unchanged until container pulls"
        );
    }

    function test_Exit_FromTokenState_FullExit() public {
        _enterToState(ONE_STATE_ID, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            NO_ALLOCATION_STATE_ID,
            "test_Exit_FromTokenState_FullExit: state after full exit not no allocation state"
        );
        assertEq(
            notion.allowance(address(strategy), address(strategyContainer)),
            DEPOSIT_AMOUNT,
            "test_Exit_FromTokenState_FullExit: incorrect token out allowance to strategy container"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            DEPOSIT_AMOUNT,
            "test_Exit_FromTokenState_FullExit: strategy notion balance unchanged until container pulls"
        );
    }

    function test_Exit_FromProtocolState_PartialExit() public {
        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);

        _enterToState(TWO_STATE_ID, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS / 2;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            TWO_STATE_ID,
            "test_Exit_FromProtocolState_PartialExit: state after exit changed"
        );
        assertEq(
            notion.allowance(address(strategy), address(strategyContainer)),
            DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromProtocolState_PartialExit: incorrect token out allowance to strategy container"
        );
        assertEq(
            notion.balanceOf(address(strategy)),
            DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromProtocolState_PartialExit: strategy notion balance should equal exited share"
        );
        assertEq(
            notion.balanceOf(address(strategy.stateToBuildingBlock(TWO_STATE_ID))),
            DEPOSIT_AMOUNT - DEPOSIT_AMOUNT.mulDiv(share, MAX_BPS),
            "test_Exit_FromProtocolState_PartialExit: mockBuildingBlock should hold remaining after partial exit"
        );
    }

    function test_Exit_FromProtocolState_FullExit() public {
        deal(address(notion), address(strategy), DEPOSIT_AMOUNT);

        console.log("allowance", notion.allowance(address(strategy), address(strategyContainer)));

        _enterToState(TWO_STATE_ID, ENTER_MIN_NAV_DELTA);

        uint256 share = MAX_BPS;
        uint256 navDelta = _calcNavDelta(share);
        vm.prank(address(strategyContainer));
        strategy.exit(share, navDelta);

        assertEq(
            strategy.currentStateId(),
            NO_ALLOCATION_STATE_ID,
            "test_Exit_FromProtocolState_FullExit: state after full exit not no allocation state"
        );
        assertEq(
            notion.allowance(address(strategy), address(strategyContainer)),
            DEPOSIT_AMOUNT,
            "test_Exit_FromProtocolState_FullExit: incorrect token out allowance to strategy container"
        );
        assertEq(
            strategy.stateNav(ONE_STATE_ID),
            DEPOSIT_AMOUNT,
            "test_Exit_FromProtocolState_FullExit: strategy notion balance should equal full deposit after exit"
        );
        assertEq(
            notion.balanceOf(address(strategy.stateToBuildingBlock(TWO_STATE_ID))),
            0,
            "test_Exit_FromProtocolState_FullExit: mockBuildingBlock notion balance should be 0 after full exit"
        );
    }

    function test_RevertIf_Exit_ShareOutOfBounds() public {
        uint256 share = 0;
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.exit(share, 0);

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategy.exit(MAX_BPS + 1, 0);
    }

    function test_RevertIf_Exit_NavResolutionModeActive() public {
        _toggleNavResolutionMode(true);

        uint256 share = MAX_BPS / 2;
        vm.prank(address(strategyContainer));
        vm.expectRevert(IStrategyTemplate.NavResolutionModeActivated.selector);
        strategy.exit(share, 0);
    }

    function test_RevertIf_Exit_NoAllocationState() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(IStrategyTemplate.CannotExitFromNoAllocationState.selector);
        strategy.exit(MAX_BPS, 0);
    }

    function test_RevertIf_Exit_SlippageCheckFailed() public {
        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(IStrategyTemplate.SlippageCheckFailed.selector, inputAmounts[0], 0, 0));
        strategy.exit(MAX_BPS, 0);
    }
}
