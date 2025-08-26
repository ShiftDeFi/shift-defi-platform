// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyTemplate} from "../StrategyTemplate.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import {ICometV3, IRewards} from "../dependencies/interfaces/compoundV3/ICompoundV3.sol";
import {IUniswapV3Router} from "../dependencies/interfaces/uniswapV3/IUniswapV3.sol";

abstract contract CompoundV3 is StrategyTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 private constant COMPOUND_V3 = bytes32(0);
    bytes32 private constant COMET_V3_UNDERLYING = keccak256("COMPOUND_V3.UNDERLYING");

    address public cometV3;
    address public cometV3Underlying;
    address public rewards;

    function allocatedNav(bytes32 stateId) public view override returns (uint256) {
        uint256 allocatedUnderlying = IERC20(cometV3).balanceOf(address(this));
        if (stateId == COMPOUND_V3) {
            return _getUsdValue(cometV3Underlying, allocatedUnderlying);
        } else if (stateId == COMET_V3_UNDERLYING) {
            uint256 underlyingBalance = IERC20(cometV3Underlying).balanceOf(address(this));
            return _getUsdValue(cometV3Underlying, underlyingBalance);
        }
        return 0;
    }

    function __CompoundV3_init(address _cometV3, address _rewards, address _containerAgent) internal onlyInitializing {
        require(_cometV3 != address(0), Errors.ZeroAddress());

        cometV3 = _cometV3;
        cometV3Underlying = ICometV3(cometV3).baseToken();
        rewards = _rewards;
        address[] memory _inputTokens = new address[](1);
        address[] memory _outputTokens = new address[](1);
        _inputTokens[0] = cometV3Underlying;
        _outputTokens[0] = cometV3Underlying;
        __StrategyTemplate_init(_inputTokens, _outputTokens, _containerAgent);
    }

    function _registerStates() internal override {
        _setOnlyTokenState(COMET_V3_UNDERLYING);
    }

    function _enter() internal override {
        uint256 amount = IERC20(cometV3Underlying).balanceOf(address(this));

        if (amount == 0) {
            return;
        }

        IERC20(cometV3Underlying).forceApprove(cometV3, amount);
        ICometV3(cometV3).supply(cometV3Underlying, amount);
    }

    function _exit(uint256 share, bytes32 stateId) internal virtual override {
        require(stateId == bytes32(0), WrongStateForExit(stateId));
        _compoundV3Exit(share);
    }

    function _emergencyExit(bytes32 toStateId) internal override {
        if (toStateId == COMET_V3_UNDERLYING) {
            _compoundV3Exit(BPS);
        } else {
            revert WrongStateForEmergencyExit(toStateId);
        }
    }

    function _claimAndSwapRewards(address _swapRouter) internal override {
        IRewards(rewards).claim(cometV3, address(this), true);
        (address token, , , ) = IRewards(rewards).rewardConfig(cometV3);
        _swapRewards(token);
    }

    function _swapRewards(address token) internal virtual;

    function _compoundV3Exit(uint256 share) internal {
        uint256 allocatedUnderlying = IERC20(cometV3).balanceOf(address(this));
        if (allocatedUnderlying == 0) {
            return;
        }
        uint256 amountForExit = share.mulDiv(allocatedUnderlying, BPS);
        IERC20(cometV3Underlying).forceApprove(cometV3, amountForExit);
        ICometV3(cometV3).withdraw(cometV3Underlying, amountForExit);
    }
}

contract CompoundV3ArbitrumUSDC is CompoundV3 {
    address private constant COMET_V3_USDC = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address private constant REWARDS = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function initialize(address _containerAgent) public override initializer {
        __CompoundV3_init(COMET_V3_USDC, REWARDS, _containerAgent);
    }

    function _swapRewards(address token) internal override {
        uint256 amountIn = IERC20(token).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }
        IERC20(token).approve(UNISWAP_V3_ROUTER, amountIn);
        // TODO: just for tests, use adapter
        IUniswapV3Router.ExactInputSingleParams memory rewardToWethParams;
        rewardToWethParams.tokenIn = token;
        rewardToWethParams.tokenOut = WETH;
        rewardToWethParams.fee = uint24(3000);
        rewardToWethParams.recipient = address(this);
        rewardToWethParams.deadline = block.timestamp;
        rewardToWethParams.amountIn = amountIn;
        rewardToWethParams.amountOutMinimum = 0;
        rewardToWethParams.sqrtPriceLimitX96 = uint160(0);
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(rewardToWethParams);
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, wethBalance);
        IUniswapV3Router.ExactInputSingleParams memory wethToUnderlyingParams;
        wethToUnderlyingParams.tokenIn = WETH;
        wethToUnderlyingParams.tokenOut = cometV3Underlying;
        wethToUnderlyingParams.fee = uint24(500);
        wethToUnderlyingParams.recipient = address(this);
        wethToUnderlyingParams.deadline = block.timestamp;
        wethToUnderlyingParams.amountIn = wethBalance;
        wethToUnderlyingParams.amountOutMinimum = 0;
        wethToUnderlyingParams.sqrtPriceLimitX96 = uint160(0);
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(wethToUnderlyingParams);
    }
}
