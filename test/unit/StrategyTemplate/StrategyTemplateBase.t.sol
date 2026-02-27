// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";

import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockStrategyContainer} from "test/mocks/MockStrategyContainer.sol";

import {Base} from "test/Base.t.sol";

abstract contract StrategyTemplateBaseTest is Base {
    using Math for uint256;

    MockStrategyContainer internal strategyContainer;
    MockStrategy internal strategy;

    bytes32 internal constant TARGET_STATE_ID_STORAGE_SLOT = bytes32(uint256(2));
    bytes32 internal constant CURRENT_STATE_ID_STORAGE_SLOT = bytes32(uint256(3));
    bytes32 internal constant STATE_BITMASKS_STORAGE_SLOT = bytes32(uint256(4));
    bytes32 internal constant NAV_RESOLUTION_MODE_STORAGE_SLOT = bytes32(uint256(11));

    bytes32 internal constant NO_ALLOCATION_STATE_ID = bytes32(uint256(0));
    bytes32 internal constant ONE_STATE_ID = bytes32(uint256(1));
    bytes32 internal constant TWO_STATE_ID = bytes32(uint256(2));
    bytes32 internal constant THREE_STATE_ID = bytes32(uint256(3));

    uint256 internal constant DEPOSIT_AMOUNT = 1_000_000 * NOTION_PRECISION;
    uint256 internal constant ENTER_MIN_NAV_DELTA = DEPOSIT_AMOUNT - 1;

    function setUp() public virtual override {
        super.setUp();

        strategyContainer = _deployMockStrategyContainer();
        strategy = _deployMockStrategy(address(strategyContainer));

        vm.startPrank(roles.defaultAdmin);
        strategyContainer.grantRole(STRATEGY_MANAGER_ROLE, roles.strategyManager);
        strategyContainer.grantRole(EMERGENCY_MANAGER_ROLE, roles.emergencyManager);
        vm.stopPrank();
    }

    function _prepareEnterInputAmounts(address _strategy) internal view returns (uint256[] memory) {
        address[] memory inputTokens = IStrategyTemplate(_strategy).getInputTokens();
        uint256[] memory inputAmounts = new uint256[](inputTokens.length);
        for (uint256 i = 0; i < inputTokens.length; i++) {
            inputAmounts[i] = DEPOSIT_AMOUNT;
        }
        return inputAmounts;
    }

    /// @dev Using StrategyTemplate.reenterToState as a wrapper for StrategyTemplate._enterToState here
    ///      because StrategyTemplate._enterToState is a private method
    function _enterToState(bytes32 toStateId, uint256 minNavDelta) internal {
        vm.prank(roles.emergencyManager);
        strategy.reenterToState(toStateId, minNavDelta);
    }

    function _getTargetStateId() internal view returns (bytes32) {
        return vm.load(address(strategy), TARGET_STATE_ID_STORAGE_SLOT);
    }

    function _setTargetStateId(bytes32 stateId) internal {
        vm.store(address(strategy), TARGET_STATE_ID_STORAGE_SLOT, stateId);
    }

    function _getStateBitmask(bytes32 stateId) internal view returns (uint256) {
        return uint256(vm.load(address(strategy), keccak256(abi.encode(stateId, STATE_BITMASKS_STORAGE_SLOT))));
    }

    function _toggleNavResolutionMode(bool isNavResolutionMode) internal {
        uint256 value = uint256(vm.load(address(strategy), NAV_RESOLUTION_MODE_STORAGE_SLOT));

        if (isNavResolutionMode) {
            value |= uint256(1);
        } else {
            value &= ~uint256(1);
        }

        vm.store(address(strategy), NAV_RESOLUTION_MODE_STORAGE_SLOT, bytes32(value));
        assertEq(
            IStrategyTemplate(address(strategy)).isNavResolutionMode(),
            isNavResolutionMode,
            "_setNavResolutionMode: nav resolution mode mismatch"
        );
    }

    function _calcNavDelta(uint256 share) internal view returns (uint256) {
        return strategy.stateNav(strategy.currentStateId()).mulDiv(share, MAX_BPS);
    }
}
