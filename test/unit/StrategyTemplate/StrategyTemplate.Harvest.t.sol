// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

contract StrategyTemplateHarvestTest is StrategyTemplateBaseTest {
    bytes32 internal constant TREASURY_STORAGE_SLOT = bytes32(uint256(14));

    function setUp() public override {
        super.setUp();

        bool isTargetState = true;
        bool isProtocolState = true;
        bool isTokenState = false;
        uint8 height = 1;

        strategy.setState(ONE_STATE_ID, isTargetState, isProtocolState, isTokenState, height);

        address[] memory inputTokens = new address[](1);
        address[] memory outputTokens = new address[](1);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);
        strategyContainer.addStrategy(address(strategy), inputTokens, outputTokens);

        uint256[] memory inputAmounts = _prepareEnterInputAmounts(address(strategy));
        deal(address(notion), address(strategyContainer), DEPOSIT_AMOUNT);

        vm.prank(address(strategyContainer));
        notion.approve(address(strategy), type(uint256).max);

        vm.prank(address(strategyContainer));
        strategy.enter(inputAmounts, ENTER_MIN_NAV_DELTA);

        vm.prank(roles.strategyManager);
        strategyContainer.setTreasury(treasury);
    }

    function test_Harvest() public {
        vm.prank(address(strategyContainer));
        uint256 navAfterHarvest = strategy.harvest();
        assertEq(navAfterHarvest, DEPOSIT_AMOUNT, "test_Harvest: nav after harvest not correct");
    }

    function test_RevertIf_Harvest_NavResolutionMode() public {
        _toggleNavResolutionMode(true);
        vm.prank(address(strategyContainer));
        vm.expectRevert(IStrategyTemplate.NavResolutionModeActivated.selector);
        strategy.harvest();
    }

    function test_Harvest_NoAllocationState_ReturnsZero() public {
        uint256 navDelta = _calcNavDelta(MAX_BPS);
        vm.prank(address(strategyContainer));
        strategy.exit(MAX_BPS, navDelta);

        vm.prank(address(strategyContainer));
        uint256 nav = strategy.harvest();
        assertEq(nav, 0, "test_Harvest_NoAllocationState_ReturnsZero: nav not zero");
    }

    function test_RevertIf_Harvest_TreasuryIsZeroAddress() public {
        vm.store(address(strategyContainer), TREASURY_STORAGE_SLOT, bytes32(uint256(0)));

        vm.prank(address(strategyContainer));
        vm.expectRevert(IStrategyTemplate.TreasuryNotSet.selector);
        strategy.harvest();
    }
}
