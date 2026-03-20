// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StrategyTemplate} from "contracts/StrategyTemplate.sol";
import {MockBuildingBlock} from "./MockBuildingBlock.sol";

contract MockStrategy is StrategyTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant MOCK_SLIPPAGE_STATE_ID = bytes32(uint256(123123));
    bytes32 public constant MOCK_REMAINDER_STATE_ID = bytes32(uint256(456456));
    uint256 public constant MOCK_REMAINDER_AMOUNT = 1;
    uint256 public constant MOCK_SLIPPAGE_AMOUNT = 1;

    bytes32 public targetStateId;

    mapping(bytes32 => bool) internal _isTokenState;
    mapping(bytes32 => bool) internal _isTargetState;
    mapping(bytes32 => MockBuildingBlock) public stateToBuildingBlock;
    mapping(bytes32 => uint256) public _stateIdToHeight;
    mapping(uint256 => bytes32) public _heightToStateId;

    error NotEnoughFunds();

    function initialize(address strategyContainer) external initializer {
        __StrategyTemplate_init(strategyContainer);
        _setState(MOCK_SLIPPAGE_STATE_ID, false, true, false, type(uint8).max - 2);
        stateToBuildingBlock[MOCK_SLIPPAGE_STATE_ID] = new MockBuildingBlock(address(this), address(_notion));
        _setState(MOCK_REMAINDER_STATE_ID, false, true, false, type(uint8).max - 1);
        stateToBuildingBlock[MOCK_REMAINDER_STATE_ID] = new MockBuildingBlock(address(this), address(_notion));
    }

    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        } else if (_isTokenState[stateId]) {
            return IERC20(_notion).balanceOf(address(this));
        } else {
            return IERC20(_notion).balanceOf(address(stateToBuildingBlock[stateId]));
        }
    }

    function setState(
        bytes32 stateId,
        bool isTargetState,
        bool isProtocolState,
        bool isTokenState,
        uint8 height
    ) external {
        _setState(stateId, isTargetState, isProtocolState, isTokenState, height);
        _stateIdToHeight[stateId] = height;
        _heightToStateId[height] = stateId;

        if (isTokenState) {
            _isTokenState[stateId] = true;
            return;
        } else {
            stateToBuildingBlock[stateId] = new MockBuildingBlock(address(this), address(_notion));
        }

        if (isTargetState) {
            _isTargetState[stateId] = true;
            targetStateId = stateId;
            return;
        }
    }

    function _enterTarget() internal override {
        IERC20(_notion).transfer(
            address(stateToBuildingBlock[targetStateId]),
            IERC20(_notion).balanceOf(address(this))
        );
    }

    function _enterState(bytes32 stateId) internal override {
        uint256 amount = IERC20(_notion).balanceOf(address(this));

        if (stateId == MOCK_SLIPPAGE_STATE_ID) {
            IERC20(_notion).transfer(address(stateToBuildingBlock[stateId]), amount - MOCK_SLIPPAGE_AMOUNT);
            return;
        }
        if (stateId == MOCK_REMAINDER_STATE_ID) {
            IERC20(_notion).transfer(address(stateToBuildingBlock[stateId]), amount - MOCK_REMAINDER_AMOUNT);
            return;
        }
        if (_isTokenState[stateId]) {
            IERC20(_notion).transferFrom(
                _strategyContainer,
                address(this),
                IERC20(_notion).balanceOf(address(_strategyContainer))
            );
            return;
        }
        if (stateId != NO_ALLOCATION_STATE_ID && !_isTokenState[stateId]) {
            IERC20(_notion).transfer(address(stateToBuildingBlock[stateId]), amount);
        }
    }

    function _exitTarget(uint256 share) internal override {
        _exitFromState(targetStateId, share);
    }

    function _exitFromState(bytes32 stateId, uint256 share) internal override {
        if (stateId == MOCK_SLIPPAGE_STATE_ID) {
            return;
        }
        uint256 amount = IERC20(_notion).balanceOf(address(stateToBuildingBlock[stateId])).mulDiv(share, MAX_BPS);
        require(amount > 0, NotEnoughFunds());

        stateToBuildingBlock[stateId].returnNotionToStrategy(amount);

        uint256 currentHeight = _stateIdToHeight[stateId];
        bytes32 lowerStateId = _heightToStateId[currentHeight - 1];

        if (lowerStateId != NO_ALLOCATION_STATE_ID && !_isTokenState[lowerStateId]) {
            _enterState(lowerStateId);
        }
    }

    function _emergencyExit(bytes32, uint256 share) internal override {
        if (_isTargetState[currentStateId()]) {
            _exitTarget(share);
        }
    }

    function _harvest(bytes32, address, uint256) internal override {}
}
