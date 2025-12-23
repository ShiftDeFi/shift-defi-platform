// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.28;

/// @title StrategyStateLib
/// @notice Bitmask helpers for encoding/decoding strategy state metadata.
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

    /**
     * @notice Checks whether the state is marked as protocol state.
     * @param state Encoded state bitmask.
     * @return True if protocol bit is set.
     */
    function isProtocolState(uint256 state) internal pure returns (bool) {
        return (state & PROTOCOL_STATE_MASK) != 0;
    }

    /**
     * @notice Checks whether the state is marked as token state.
     * @param state Encoded state bitmask.
     * @return True if token bit is set.
     */
    function isTokenState(uint256 state) internal pure returns (bool) {
        return (state & TOKEN_STATE_MASK) != 0;
    }

    /**
     * @notice Checks whether the state is marked as target state.
     * @param state Encoded state bitmask.
     * @return True if target bit is set.
     */
    function isTargetState(uint256 state) internal pure returns (bool) {
        return (state & TARGET_STATE_MASK) != 0;
    }

    /**
     * @notice Returns the height (depth) encoded in the state.
     * @param state Encoded state bitmask.
     * @return Height value (lowest 8 bits).
     */
    function height(uint256 state) internal pure returns (uint256) {
        return state & HEIGHT_MASK;
    }

    /**
     * @notice Creates an encoded state bitmask from flags and height.
     * @dev Reverts if flags combination is invalid (target+token together, or none set).
     * @param _isTargetState Whether the state is target.
     * @param _isProtocolState Whether the state is protocol.
     * @param _isTokenState Whether the state is token.
     * @param _height Height value (0-255).
     * @return Encoded state bitmask.
     */
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
