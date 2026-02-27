// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BridgeAdapter} from "contracts/BridgeAdapter.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {RingCacheLibrary} from "contracts/libraries/helpers/RingCacheLibrary.sol";

contract MockBridgeAdapter is BridgeAdapter {
    using SafeERC20 for IERC20;
    using RingCacheLibrary for RingCacheLibrary.RingCache;

    function initialize(address defaultAdmin, address governance) public initializer {
        __BridgeAdapter_init(defaultAdmin, governance);
    }

    function finalizeBridge(address claimer, address token, uint256 amount) public {
        _finalizeBridge(claimer, token, amount);
    }

    function validateBridgeInstruction(IBridgeAdapter.BridgeInstruction calldata instruction) public view {
        _validateBridgeInstruction(instruction);
    }

    function slippageCapPct() external view returns (uint256 result) {
        assembly {
            result := sload(4)
        }
    }

    function isCached(address token, uint256 chainTo, uint256 amount, address receiver) external view returns (bool) {
        bytes32 key = keccak256(abi.encode(token, chainTo, amount, receiver));

        RingCacheLibrary.RingCache storage cache;
        assembly {
            cache.slot := 5
        }

        return cache.exists(key);
    }

    function _bridge(
        BridgeInstruction calldata bridgeInstruction,
        address,
        address
    ) internal virtual override returns (uint256) {
        return bridgeInstruction.amount;
    }
}
