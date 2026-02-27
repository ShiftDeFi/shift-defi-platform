// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockBuildingBlock {
    using SafeERC20 for IERC20;

    address public strategy;
    address public notion;

    error NotStrategy();
    error ZeroAddress();

    constructor(address _strategy, address _notion) {
        require(_strategy != address(0), ZeroAddress());
        require(_notion != address(0), ZeroAddress());
        strategy = _strategy;
        notion = _notion;
    }

    function returnNotionToStrategy(uint256 amount) external {
        require(msg.sender == strategy, NotStrategy());
        IERC20(notion).safeTransfer(strategy, amount);
    }
}
