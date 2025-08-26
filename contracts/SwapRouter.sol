// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";

contract SwapRouter is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ISwapRouter {
    using SafeERC20 for IERC20;

    bytes32 private constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    mapping(address => bool) public whitelistedAdapters;

    modifier onlyWhitelistManager() {
        // onlyrole
        require(hasRole(WHITELIST_MANAGER_ROLE, msg.sender), NotWhitelistManager(msg.sender));
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        __AccessControl_init();
        __ReentrancyGuard_init();
    }

    function whitelistSwapAdapter(address adapter) external onlyWhitelistManager {
        // add check
        whitelistedAdapters[adapter] = true;
        emit SwapAdapterWhitelisted(adapter);
    }

    // todo: blacklist
    function blacklistSwapAdapter(address adapter) external onlyWhitelistManager {
        whitelistedAdapters[adapter] = false;
        emit SwapAdapterBlacklisted(adapter);
    }

    function swap(SwapInstruction calldata instruction) external payable nonReentrant returns (uint256) {
        require(whitelistedAdapters[instruction.adapter], AdapterNotWhitelisted(instruction.adapter));

        IERC20(instruction.tokenIn).safeTransferFrom(msg.sender, address(this), instruction.amountIn);
        IERC20(instruction.tokenIn).forceApprove(instruction.adapter, instruction.amountIn);
        uint256 amountOutBefore = IERC20(instruction.tokenOut).balanceOf(msg.sender);
        ISwapAdapter(instruction.adapter).swap(
            instruction.tokenIn,
            instruction.tokenOut,
            instruction.amountIn,
            instruction.minAmountOut,
            msg.sender,
            instruction.payload
        );
        uint256 amountOutAfter = IERC20(instruction.tokenOut).balanceOf(msg.sender);
        require(
            amountOutAfter - amountOutBefore >= instruction.minAmountOut,
            SlippageNotMet(amountOutBefore, amountOutAfter, instruction.minAmountOut) // todo: inline with other slippage checks
        );

        emit Swap(msg.sender, instruction.tokenIn, instruction.tokenOut, instruction.amountIn, amountOutAfter);
        return amountOutAfter - amountOutBefore; // cache
    }
}
