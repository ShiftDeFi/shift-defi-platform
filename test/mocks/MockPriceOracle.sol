// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceOracle} from "contracts/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    uint8 public decimals;
    mapping(address => uint256) public prices;

    constructor(uint8 decimals_) {
        setDecimals(decimals_);
    }

    function setDecimals(uint8 decimals_) public {
        decimals = decimals_;
    }

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view override returns (uint256, uint8) {
        return (prices[token], decimals);
    }
}
