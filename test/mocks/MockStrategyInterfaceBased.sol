// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategyInterfaceBased is IStrategyTemplate {
    uint256 internal constant BPS = 10000;

    // Enter return values
    uint256 nav1;
    uint256 nav0;

    bool hasRemainder;
    uint256[] remainingAmounts;

    // getInputTokens return values
    address[] inputTokens;

    // getOutputTokens return values
    address[] outputTokens;

    bool _navResolutionMode;

    function approveToken(address token, uint256 amount, address spender) public {
        IERC20(token).approve(spender, amount);
    }

    function craftNav1(uint256 navAfterEnter_) public {
        nav1 = navAfterEnter_;
    }

    function craftNav0(uint256 navAfterHarvest_) public {
        nav0 = navAfterHarvest_;
    }

    function craftRemainingAmounts(uint256[] memory remainingAmounts_) public {
        hasRemainder = true;
        remainingAmounts = new uint256[](remainingAmounts_.length);
        for (uint256 i = 0; i < remainingAmounts_.length; i++) {
            remainingAmounts[i] = remainingAmounts_[i];
        }
    }

    function enter(uint256[] memory inputAmounts, uint256) external payable returns (uint256, bool, uint256[] memory) {
        for (uint256 i = 0; i < inputAmounts.length; i++) {
            IERC20(inputTokens[i]).transferFrom(msg.sender, address(this), inputAmounts[i]);
        }
        return (nav1, hasRemainder, remainingAmounts);
    }

    function exit(uint256 share, uint256) external payable returns (address[] memory, uint256[] memory) {
        uint256[] memory _outputTokensAmounts = new uint256[](outputTokens.length);
        for (uint256 i = 0; i < outputTokens.length; i++) {
            _outputTokensAmounts[i] = (IERC20(outputTokens[i]).balanceOf(address(this)) * share) / BPS;
        }
        return (outputTokens, _outputTokensAmounts);
    }

    function harvest() external payable returns (uint256) {
        return nav0;
    }

    function emergencyExit(bytes32 toStateId, uint256 share) external payable {}

    function emergencyExitMultiple(bytes32[] calldata toStateIds, uint256[] calldata shares) external payable {}

    function tryEmergencyExit(bytes32 toStateId, uint256 share) external {}

    function setInputTokens(address[] memory inputTokens_) external {
        inputTokens = new address[](inputTokens_.length);
        for (uint256 i = 0; i < inputTokens_.length; i++) {
            inputTokens[i] = inputTokens_[i];
        }
    }

    function setOutputTokens(address[] memory outputTokens_) external {
        outputTokens = new address[](outputTokens_.length);
        for (uint256 i = 0; i < outputTokens_.length; i++) {
            outputTokens[i] = outputTokens_[i];
        }
    }

    function getTokens() external pure returns (address[] memory, address[] memory) {
        return (new address[](0), new address[](0));
    }

    function stateNav(bytes32) external pure returns (uint256) {
        return 0;
    }

    function currentStateId() external pure returns (bytes32) {
        return bytes32(0);
    }

    function currentStateNav() external pure returns (uint256) {
        return 0;
    }

    function isNavResolutionMode() external view returns (bool) {
        return _navResolutionMode;
    }

    function getInputTokens() external view returns (address[] memory) {
        return inputTokens;
    }

    function getOutputTokens() external view returns (address[] memory) {
        return outputTokens;
    }

    function getTokenAmountInNotion(address, uint256) external pure returns (uint256) {
        return 0;
    }
}
