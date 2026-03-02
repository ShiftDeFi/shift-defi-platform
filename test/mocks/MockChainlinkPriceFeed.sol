// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "contracts/dependencies/interfaces/chainlink/AggregatorV3Interface.sol";

contract MockChainlinkPriceFeed is AggregatorV3Interface {
    int256 public answer;
    uint8 public decimals;
    uint256 public updatedAt;

    constructor(int256 _answer, uint8 _decimals) {
        answer = _answer;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function getRoundData(
        uint80
    )
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function description() external pure returns (string memory) {
        return "Mock Chainlink Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
