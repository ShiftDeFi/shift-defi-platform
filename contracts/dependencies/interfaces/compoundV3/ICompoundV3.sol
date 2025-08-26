// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICometV3 {
    function baseToken() external view returns (address);
    function supply(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
}

interface IRewards {
    function claim(address comet, address src, bool accrue) external;
    function rewardConfig(address comet) external view returns (address, uint64, bool, uint256);
}
