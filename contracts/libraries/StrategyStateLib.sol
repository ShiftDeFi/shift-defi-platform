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
        bool _isTargetState,
        bool _isProtocolState,
        bool _isTokenState,
        uint8 _height
    ) internal pure returns (uint256) {
        if (_isTargetState && _isTokenState) {
            revert InconsistentState();
        }
        if (!_isTargetState && !_isProtocolState && !_isTokenState) {
            revert ZeroState();
        }
        return
            (_isTargetState ? TARGET_STATE_MASK : 0) |
            (_isProtocolState ? PROTOCOL_STATE_MASK : 0) |
            (_isTokenState ? TOKEN_STATE_MASK : 0) |
            _height;
    }
}
