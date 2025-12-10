// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "./libraries/helpers/Errors.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

abstract contract Container is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IContainer {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    address public vault;
    address public notion;

    address public swapRouter;

    EnumerableSet.AddressSet private _whitelistedTokens;

    mapping(address => uint256) private _whitelistedTokensDustThresholds;

    modifier onlyVault() {
        require(msg.sender == vault, Errors.Unauthorized());
        _;
    }

    function __Container_init(ContainerInitParams memory params) internal onlyInitializing {
        require(params.vault != address(0), Errors.ZeroAddress());
        vault = params.vault;
        require(params.notion != address(0), Errors.ZeroAddress());
        notion = params.notion;

        _whitelistedTokens.add(notion);
        _setSwapRouter(params.swapRouter);

        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(OPERATOR_ROLE, params.operator);
        _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdmin);
    }

    // ---- Token management logic ----

    function isTokenWhitelisted(address token) external view override returns (bool) {
        return _isTokenWhitelisted(token);
    }

    function whitelistToken(address token) external onlyRole(TOKEN_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(_whitelistedTokens.add(token), AlreadyWhitelistedToken());
        IERC20(token).safeIncreaseAllowance(swapRouter, type(uint256).max);
        emit TokenWhitelistUpdated(token, true);
    }

    function blacklistToken(address token) external onlyRole(TOKEN_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(_whitelistedTokens.remove(token), NotWhitelistedToken(token));
        _whitelistedTokensDustThresholds[token] = 0;
        IERC20(token).forceApprove(swapRouter, 0);
        emit TokenWhitelistUpdated(token, false);
    }

    function setWhitelistedTokenDustThreshold(address token, uint256 threshold) external onlyRole(TOKEN_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(threshold > 0, Errors.ZeroAmount());
        require(_whitelistedTokens.contains(token), NotWhitelistedToken(token));

        _whitelistedTokensDustThresholds[token] = threshold;
        emit WhitelistedTokenDustThresholdUpdated(token, threshold);
    }

    function _isTokenWhitelisted(address token) internal view returns (bool) {
        return _whitelistedTokens.contains(token);
    }

    function _validateToken(address token) internal view {
        require(_isTokenWhitelisted(token), IContainer.NotWhitelistedToken(token));
        require(token != address(0), Errors.ZeroAddress());
    }

    function _validateWhitelistedTokensBeforeReport(bool ignoreNotion, bool ignoreDust) internal view returns (bool) {
        uint256 length = _whitelistedTokens.length();
        for (uint256 i = 0; i < length; i++) {
            address token = _whitelistedTokens.at(i);
            if (ignoreNotion && token == notion) {
                continue;
            }
            uint256 dustThreshold = !ignoreDust ? 0 : _whitelistedTokensDustThresholds[token];
            if (IERC20(token).balanceOf(address(this)) > dustThreshold) {
                return false;
            }
        }
        return true;
    }

    function _hasOnlyNotionToken() internal view returns (bool) {
        return _validateWhitelistedTokensBeforeReport(true, true) && IERC20(notion).balanceOf(address(this)) > 0;
    }

    function setSwapRouter(address newSwapRouter) external onlyRole(TOKEN_MANAGER_ROLE) {
        require(newSwapRouter != address(0), Errors.ZeroAddress());
        _setSwapRouter(newSwapRouter);
    }

    function _setSwapRouter(address newSwapRouter) internal {
        address previousSwapRouter = swapRouter;
        swapRouter = newSwapRouter;
        if (previousSwapRouter != address(0)) {
            _dropApprovesFromWhitelistedTokens(previousSwapRouter);
        }
        _approveWhitelistedTokens(newSwapRouter);
        emit SwapRouterUpdated(previousSwapRouter, newSwapRouter);
    }

    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata instructions) external onlyRole(OPERATOR_ROLE) {
        require(instructions.length > 0, Errors.ZeroArrayLength());
        _prepareLiquidity(instructions);
    }

    function _prepareLiquidity(ISwapRouter.SwapInstruction[] calldata instructions) internal {
        uint256 length = instructions.length;
        for (uint256 i = 0; i < length; ++i) {
            _swap(instructions[i]);
        }
    }

    /**
     * @dev Performs a single swap using the swap router.
     * @param instruction The swap instruction containing tokenIn, tokenOut, amountIn, etc.
     */
    function _swap(ISwapRouter.SwapInstruction calldata instruction) internal {
        require(_isTokenWhitelisted(instruction.tokenIn), NotWhitelistedToken(instruction.tokenIn));
        require(_isTokenWhitelisted(instruction.tokenOut), NotWhitelistedToken(instruction.tokenOut));

        ISwapRouter(swapRouter).swap(instruction);
    }

    function _dropApprovesFromWhitelistedTokens(address addr) internal {
        uint256 length = _whitelistedTokens.length();
        for (uint256 i = 0; i < length; i++) {
            address token = _whitelistedTokens.at(i);
            IERC20(token).forceApprove(addr, 0);
        }
    }

    function _approveWhitelistedTokens(address addr) internal {
        uint256 length = _whitelistedTokens.length();
        for (uint256 i = 0; i < length; i++) {
            address token = _whitelistedTokens.at(i);
            IERC20(token).safeIncreaseAllowance(addr, type(uint256).max);
        }
    }
}
