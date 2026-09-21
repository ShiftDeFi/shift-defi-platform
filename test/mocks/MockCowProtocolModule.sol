// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {CowProtocolModule} from "contracts/CowProtocolModule.sol";

contract MockCowProtocolModule is CowProtocolModule {
    mapping(address => bool) internal _whitelistedTokens;

    function whitelistToken(address token) external {
        _whitelistedTokens[token] = true;
    }

    /**
     * @dev Writes the namespace directly, bypassing the validation _setCowAdapter applies.
     * @param newCowAdapter The address to write.
     */
    function setCowAdapterRaw(address newCowAdapter) external {
        _getCowProtocolModuleStorage().cowAdapter = newCowAdapter;
    }

    function requireNoPendingOrders() external {
        _requireNoPendingOrders();
    }

    function setCowAdapter(address newCowAdapter) external {
        _setCowAdapter(newCowAdapter);
    }

    function placeCowOrder(ICowProtocolAdapter.OrderParams calldata params) external returns (bytes32) {
        return _placeCowOrder(params);
    }

    function cancelCowOrder(bytes32 orderDigest) external {
        _cancelCowOrder(orderDigest);
    }

    function resolveCowOrder(bytes32 orderDigest) external {
        _resolveCowOrder(orderDigest);
    }

    function sweepCowAdapter(address token) external {
        _sweepCowAdapter(token);
    }

    function sweepCowLane(uint256 laneIndex, address token) external {
        _sweepCowLane(laneIndex, token);
    }

    /// @dev Stands in for the whitelist each inheriting contract already keeps.
    function _isCowTokenWhitelisted(address token) internal view override returns (bool) {
        return _whitelistedTokens[token];
    }
}
