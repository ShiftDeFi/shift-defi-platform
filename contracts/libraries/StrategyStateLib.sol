// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.28;

library StrategyStateLib {
    uint256 constant TOKEN_STATE_POSITION = 8;
    uint256 constant PROTOCOL_STATE_POSITION = 9;
    uint256 constant TARGET_STATE_POSITION = 10;

    uint256 constant TOKEN_STATE_MASK = 1 << TOKEN_STATE_POSITION;
    uint256 constant PROTOCOL_STATE_MASK = 1 << PROTOCOL_STATE_POSITION;
    uint256 constant TARGET_STATE_MASK = 1 << TARGET_STATE_POSITION;
    uint256 constant HEIGHT_MASK = 255;

    error InconsistentState();
    error ZeroState();

    function isProtocolState(uint256 state) internal pure returns (bool) {
        return (state & PROTOCOL_STATE_MASK) != 0;
    }
    function isTokenState(uint256 state) internal pure returns (bool) {
        return (state & TOKEN_STATE_MASK) != 0;
    }

    function isTargetState(uint256 state) internal pure returns (bool) {
        return (state & TARGET_STATE_MASK) != 0;
    }

    function height(uint256 state) internal pure returns (uint256) {
        return state & HEIGHT_MASK;
    }

    function createState(
        bool isTargetState,
        bool isProtocolState,
        bool isTokenState,
        uint8 height
    ) internal pure returns (uint256) {
        if (isTargetState && isTokenState) {
            revert InconsistentState();
        }
        if (!isTargetState && !isProtocolState && !isTokenState) {
            revert ZeroState();
        }
        return
            (isTargetState ? TARGET_STATE_MASK : 0) |
            (isProtocolState ? PROTOCOL_STATE_MASK : 0) |
            (isTokenState ? TOKEN_STATE_MASK : 0) |
            height;
    }
}
