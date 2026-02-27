// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IChainlinkPriceFeed} from "contracts/dependencies/interfaces/chainlink/IChainlinkPriceFeed.sol";

contract MockChainlinkPriceFeed is IChainlinkPriceFeed {
    int256 public answer;
    uint8 public decimals;

    constructor(int256 _answer, uint8 _decimals) {
        answer = _answer;
        decimals = _decimals;
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }
}
