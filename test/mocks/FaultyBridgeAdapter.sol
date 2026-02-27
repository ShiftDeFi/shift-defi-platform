// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

contract FaultyBridgeAdapter is IBridgeAdapter {
    using SafeERC20 for IERC20;

    function setSlippageCapPct(uint256) external override {}

    function bridge(BridgeInstruction calldata instruction, address) external override returns (uint256) {
        IERC20(instruction.token).safeTransferFrom(msg.sender, address(this), instruction.amount / 2);
        return instruction.amount;
    }

    function claim(address token) external override returns (uint256) {
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        return IERC20(token).balanceOf(address(this));
    }

    function bridgePaths(address token, uint256) external pure override returns (address) {
        return token;
    }

    function peers(uint256) external pure override returns (address) {}

    function whitelistedBridgers(address) external view override returns (bool) {}

    function claimableAmounts(address, address) external view override returns (uint256) {}

    function setBridgePath(address, uint256, address) external override {}

    function setPeer(uint256, address) external override {}

    function whitelistBridger(address) external override {}

    function blacklistBridger(address) external override {}

    function retryBridge(BridgeInstruction calldata, address) external override {}
}
