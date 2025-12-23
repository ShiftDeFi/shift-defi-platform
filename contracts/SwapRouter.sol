// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";

import {Errors} from "./libraries/helpers/Errors.sol";

contract SwapRouter is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ISwapRouter {
    using SafeERC20 for IERC20;

    bytes32 private constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    mapping(address => bool) public whitelistedAdapters;
    mapping(address => mapping(address => PredefinedSwapParameters)) public predefinedSwapParameters;

    modifier onlyWhitelistManager() {
        // onlyrole
        require(hasRole(WHITELIST_MANAGER_ROLE, msg.sender), NotWhitelistManager(msg.sender));
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the SwapRouter contract.
     * @dev Sets up access control and grants DEFAULT_ADMIN_ROLE to the default admin.
     * @param defaultAdmin The address to receive DEFAULT_ADMIN_ROLE.
     */
    function initialize(address defaultAdmin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        __AccessControl_init();
        __ReentrancyGuard_init();
    }

    /// @inheritdoc ISwapRouter
    function whitelistSwapAdapter(address adapter) external onlyWhitelistManager {
        require(!whitelistedAdapters[adapter], Errors.AlreadyWhitelisted());
        whitelistedAdapters[adapter] = true;
        emit SwapAdapterWhitelisted(adapter);
    }

    /// @inheritdoc ISwapRouter
    function blacklistSwapAdapter(address adapter) external onlyWhitelistManager {
        require(whitelistedAdapters[adapter], Errors.AlreadyBlacklisted());
        whitelistedAdapters[adapter] = false;
        emit SwapAdapterBlacklisted(adapter);
    }

    /// @inheritdoc ISwapRouter
    function setPredefinedSwapParameters(
        address tokenIn,
        address tokenOut,
        address adapter,
        bytes calldata payload
    ) external onlyWhitelistManager {
        require(tokenIn != address(0), Errors.ZeroAddress());
        require(tokenOut != address(0), Errors.ZeroAddress());
        require(adapter != address(0), Errors.ZeroAddress());
        require(whitelistedAdapters[adapter], AdapterNotWhitelisted(adapter));
        predefinedSwapParameters[tokenIn][tokenOut] = PredefinedSwapParameters(adapter, payload);
        emit PredefinedSwapParametersSet(tokenIn, tokenOut, adapter, payload);
    }

    /// @inheritdoc ISwapRouter
    function tryPredefinedSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (bool, uint256) {
        address adapter = predefinedSwapParameters[tokenIn][tokenOut].adapter;
        bytes memory payload = predefinedSwapParameters[tokenIn][tokenOut].payload;
        if (adapter == address(0)) {
            return (false, 0);
        }
        return (
            true,
            swap(
                ISwapRouter.SwapInstruction({
                    adapter: adapter,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    minAmountOut: minAmountOut,
                    payload: payload
                })
            )
        );
    }

    /// @inheritdoc ISwapRouter
    function swap(SwapInstruction memory instruction) public payable nonReentrant returns (uint256) {
        require(whitelistedAdapters[instruction.adapter], AdapterNotWhitelisted(instruction.adapter));

        IERC20(instruction.tokenIn).safeTransferFrom(msg.sender, address(this), instruction.amountIn);
        IERC20(instruction.tokenIn).forceApprove(instruction.adapter, instruction.amountIn);
        uint256 amountOutBefore = IERC20(instruction.tokenOut).balanceOf(address(this));
        ISwapAdapter(instruction.adapter).swap(
            instruction.tokenIn,
            instruction.tokenOut,
            instruction.amountIn,
            instruction.minAmountOut,
            address(this),
            instruction.payload
        );
        uint256 amountOutAfter = IERC20(instruction.tokenOut).balanceOf(address(this));
        uint256 deltaTokenOut = amountOutAfter - amountOutBefore;
        require(
            deltaTokenOut >= instruction.minAmountOut,
            SlippageNotMet(amountOutBefore, amountOutAfter, instruction.minAmountOut)
        );

        IERC20(instruction.tokenOut).safeTransfer(msg.sender, deltaTokenOut);

        emit Swap(msg.sender, instruction.tokenIn, instruction.tokenOut, instruction.amountIn, deltaTokenOut);
        return deltaTokenOut;
    }
}
