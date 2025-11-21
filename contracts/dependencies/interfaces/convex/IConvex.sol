// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IConvexBooster {
    function deposit(uint256 amount, uint256 index) external;
    function depositAll(uint256 index) external;
    function withdraw(uint256 amount) external;
    function claimRewards() external;
    function getReward() external view returns (uint256);
    function getRewardAmounts() external view returns (uint256[] memory);
    function getRewardTokens() external view returns (address[] memory);

    function poolInfo(uint256 index) external view returns (address, address, address, bool, address);
}

interface IConvexRewardPool {
    function balanceOf(address account) external view returns (uint256);
    function getReward(address account) external;
    function withdraw(uint256 amount, bool claim) external;
    function withdrawAll(bool claim) external;
    function rewardLength() external view returns (uint256);
    function rewards(uint256 index) external view returns (address);
}
