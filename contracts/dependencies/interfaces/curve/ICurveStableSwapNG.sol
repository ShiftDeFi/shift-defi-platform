// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICurveStableSwapNG is IERC20 {
    function coins(uint256 index) external view returns (address);
    function get_balances() external view returns (uint256[] memory);
    function totalSupply() external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount) external;
    function remove_liquidity(uint256 amount, uint256[] memory min_amounts) external;
}

interface ICurveGauge is IERC20 {
    function lp_token() external view returns (address);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
}
