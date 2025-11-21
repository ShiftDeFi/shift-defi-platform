// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyTemplate} from "../StrategyTemplate.sol";

import {IConvexBooster, IConvexRewardPool} from "../dependencies/interfaces/convex/IConvex.sol";
import {ICurveStableSwapNG} from "../dependencies/interfaces/curve/ICurveStableSwapNG.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IPriceOracleAggregator} from "../interfaces/IPriceOracleAggregator.sol";
import {IContainer} from "../interfaces/IContainer.sol";
import {IStrategyContainer} from "../interfaces/IStrategyContainer.sol";

import {IConvexCurve} from "./interfaces/IConvexCurve.sol";

import "hardhat/console.sol";

contract ConvexCurveArbitrumcrvUSDUSDC is Initializable, ReentrancyGuardUpgradeable, StrategyTemplate, IConvexCurve {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 private constant CONVEX_ALLOCATION_STATE_ID = keccak256("CONVEX_ALLOCATION_STATE_ID");
    bytes32 private constant CURVE_ALLOCATION_STATE_ID = keccak256("CURVE_ALLOCATION_STATE_ID");
    bytes32 private constant CRVUSD_USDC_TOKENS_STATE_ID = keccak256("CRVUSD_USDC_TOKENS_STATE_ID");
    bytes32 private constant ONLY_USDC_STATE_ID = keccak256("ONLY_USDC_STATE_ID");

    uint256 private _convexPoolId;
    address private _booster;
    address private _rewardPool;
    address private _pool;

    address private constant _usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address private constant _crvUSD = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;

    function initialize(address agent, address booster, uint256 convexPoolId) public initializer {
        __StrategyTemplate_init(agent);

        bool _isShutdown;

        _setState(CONVEX_ALLOCATION_STATE_ID, true, true, false, 2);
        _setState(CURVE_ALLOCATION_STATE_ID, false, true, false, 1);
        _setState(CRVUSD_USDC_TOKENS_STATE_ID, false, false, true, 0);
        _setState(ONLY_USDC_STATE_ID, false, false, true, 0);

        _booster = booster;
        _convexPoolId = convexPoolId;
        (_pool, , _rewardPool, _isShutdown, ) = IConvexBooster(_booster).poolInfo(convexPoolId);
        require(!_isShutdown, ConvexPoolShutdowned(convexPoolId));
    }

    function stateNav(bytes32 stateId) public view override returns (uint256) {
        if (stateId == CONVEX_ALLOCATION_STATE_ID) {
            return convexStateNav();
        } else if (stateId == CURVE_ALLOCATION_STATE_ID) {
            return curveStateNav();
        } else if (stateId == CRVUSD_USDC_TOKENS_STATE_ID) {
            return crvUSDUSDCStateNav();
        } else if (stateId == ONLY_USDC_STATE_ID) {
            return usdcStateNav();
        } else if (stateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        }
        revert StateNotFound(stateId);
    }

    function convexStateNav() public view returns (uint256) {
        uint256 lpLocked = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        return _estimateCurveNavInNotion(lpLocked);
    }

    function curveStateNav() public view returns (uint256) {
        uint256 lpLocked = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        uint256 lpOnBalance = IERC20(_pool).balanceOf(address(this));
        return _estimateCurveNavInNotion(lpLocked + lpOnBalance);
    }

    function crvUSDUSDCStateNav() public view returns (uint256) {
        uint256 lpLocked = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        uint256 lpOnBalance = IERC20(_pool).balanceOf(address(this));
        uint256 crvUSDBalance = IERC20(_crvUSD).balanceOf(address(this));
        uint256 usdcBalance = IERC20(_usdc).balanceOf(address(this));

        uint256 curveTotalLp = IERC20(_pool).totalSupply();
        uint256[] memory tokenTotalBalances = new uint256[](2);
        tokenTotalBalances = ICurveStableSwapNG(_pool).get_balances();
        uint256 token0Owed = lpLocked.mulDiv(tokenTotalBalances[0], curveTotalLp, Math.Rounding.Floor) + crvUSDBalance;
        uint256 token1Owed = lpLocked.mulDiv(tokenTotalBalances[1], curveTotalLp, Math.Rounding.Floor) + usdcBalance;
        address priceOracle = IStrategyContainer(_strategyContainer).priceOracle();
        uint256 token0Value = IPriceOracleAggregator(priceOracle).getRelativeValueUnified(_usdc, _notion, token0Owed);
        uint256 token1Value = IPriceOracleAggregator(priceOracle).getRelativeValueUnified(_crvUSD, _notion, token1Owed);
        return token0Value + token1Value;
    }

    function usdcStateNav() public view returns (uint256) {
        uint256 lpLocked = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        uint256 lpOnBalance = IERC20(_pool).balanceOf(address(this));
        uint256 usdcBalance = IERC20(_usdc).balanceOf(address(this));
        uint256 curveTotalLp = IERC20(_pool).totalSupply();
        uint256[] memory tokenTotalBalances = new uint256[](2);
        tokenTotalBalances = ICurveStableSwapNG(_pool).get_balances();
        uint256 token0Owed = lpLocked.mulDiv(tokenTotalBalances[0], curveTotalLp, Math.Rounding.Floor) + usdcBalance;
        address priceOracle = IStrategyContainer(_strategyContainer).priceOracle();
        uint256 token0Value = IPriceOracleAggregator(priceOracle).getRelativeValueUnified(_usdc, _notion, token0Owed);
        return token0Value;
    }

    function _estimateCurveNavInNotion(uint256 curveLpAmount) private view returns (uint256) {
        CurveStableNGNavLocalVars memory vars;
        vars.curveTotalSupply = IERC20(_pool).totalSupply();
        vars.totalUnderlyingTokensInPool = new uint256[](2);
        vars.totalUnderlyingTokensInPool = ICurveStableSwapNG(_pool).get_balances();
        vars.token0OwedByStrategy = curveLpAmount.mulDiv(
            vars.totalUnderlyingTokensInPool[0],
            vars.curveTotalSupply,
            Math.Rounding.Floor
        );
        vars.token1OwedByStrategy = curveLpAmount.mulDiv(
            vars.totalUnderlyingTokensInPool[1],
            vars.curveTotalSupply,
            Math.Rounding.Floor
        );
        vars.token0AmountInNotion = getTokenAmountInNotion(_crvUSD, vars.token0OwedByStrategy);
        vars.token1AmountInNotion = getTokenAmountInNotion(_usdc, vars.token1OwedByStrategy);
        return vars.token0AmountInNotion + vars.token1AmountInNotion;
    }
    function _enterState(bytes32 stateId) internal override {
        if (stateId == CONVEX_ALLOCATION_STATE_ID) {
            _enterConvex();
        } else if (stateId == CURVE_ALLOCATION_STATE_ID) {
            _enterCurve();
        } else if (stateId == CRVUSD_USDC_TOKENS_STATE_ID) {
            _enterCrvUSD();
        } else if (stateId == ONLY_USDC_STATE_ID) {
            _enterOnlyUSDC();
        } else {
            revert StateNotFound(stateId);
        }
    }

    function _enterTarget() internal override {
        _enterCurve();
        _enterConvex();
    }

    function _enterConvex() internal {
        uint256 lpAmount = IERC20(_pool).balanceOf(address(this));
        if (lpAmount > 0) {
            IERC20(_pool).forceApprove(_booster, lpAmount);
            IConvexBooster(_booster).depositAll(_convexPoolId);
        }
    }
    function _enterCurve() internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = IERC20(_crvUSD).balanceOf(address(this));
        amounts[1] = IERC20(_usdc).balanceOf(address(this));
        if (amounts[0] > 0) {
            IERC20(_crvUSD).forceApprove(_pool, amounts[0]);
        }
        if (amounts[1] > 0) {
            IERC20(_usdc).forceApprove(_pool, amounts[1]);
        }
        if (amounts[0] > 0 || amounts[1] > 0) {
            ICurveStableSwapNG(_pool).add_liquidity(amounts, 0);
        }
    }
    function _enterCrvUSD() internal {}

    function _enterOnlyUSDC() internal {}

    function _exitTarget(uint256 share) internal override {
        uint256 convexLiquidity = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        uint256 liquidityToWithdraw = convexLiquidity.mulDiv(share, BPS, Math.Rounding.Floor);
        require(liquidityToWithdraw > 0, NotEnoughLiquidity());
        IConvexRewardPool(_rewardPool).withdraw(liquidityToWithdraw, false);
        uint256 curveLiquidityToWithdrawn = IERC20(_pool).balanceOf(address(this));
        require(curveLiquidityToWithdrawn > 0, NotEnoughLiquidity());
        ICurveStableSwapNG(_pool).remove_liquidity(curveLiquidityToWithdrawn, new uint256[](2));
    }
    function _exitFromState(bytes32 stateId, uint256 liquidity) internal override {
        if (stateId == CONVEX_ALLOCATION_STATE_ID) {
            _exitConvex(liquidity);
        } else if (stateId == CURVE_ALLOCATION_STATE_ID) {
            _exitCurve(liquidity);
        } else if (stateId == CRVUSD_USDC_TOKENS_STATE_ID) {
            _exitCrvUSD(liquidity);
        } else {
            revert StateNotFound(stateId);
        }
    }
    function _emergencyExit(bytes32 toStateId, uint256 share) internal override {
        if (toStateId == CURVE_ALLOCATION_STATE_ID) {
            _exitConvex(share);
        } else if (toStateId == CRVUSD_USDC_TOKENS_STATE_ID) {
            _exitCurve(share);
        } else if (toStateId == ONLY_USDC_STATE_ID) {
            _exitCrvUSD(share);
        } else {
            revert StateNotFound(toStateId);
        }
    }
    function _exitConvex(uint256 share) internal {
        uint256 convexLiquidity = IConvexRewardPool(_rewardPool).balanceOf(address(this));
        uint256 liquidityToWithdraw = convexLiquidity.mulDiv(share, BPS, Math.Rounding.Floor);
        require(liquidityToWithdraw > 0, NotEnoughLiquidity());
        IConvexRewardPool(_rewardPool).withdraw(liquidityToWithdraw, false);
    }
    function _exitCurve(uint256 share) internal {
        uint256 curveLiquidity = IERC20(_pool).balanceOf(address(this));
        uint256 liquidityToWithdraw = curveLiquidity.mulDiv(share, BPS, Math.Rounding.Floor);
        require(liquidityToWithdraw > 0, NotEnoughLiquidity());
        ICurveStableSwapNG(_pool).remove_liquidity(liquidityToWithdraw, new uint256[](2));
    }
    function _exitCrvUSD(uint256 share) internal {
        uint256 crvUSDBalance = IERC20(_crvUSD).balanceOf(address(this));
        uint256 amountToWithdraw = crvUSDBalance.mulDiv(share, BPS, Math.Rounding.Floor);
        require(amountToWithdraw > 0, NotEnoughLiquidity());
        IERC20(_crvUSD).forceApprove(_pool, amountToWithdraw);
        ICurveStableSwapNG(_pool).exchange(0, 1, amountToWithdraw, 0);
    }

    function _harvest(address swapRouter, address treasury, uint256 feePct) internal override {
        IConvexRewardPool(_rewardPool).getReward(address(this));
        uint256 rewardLength = IConvexRewardPool(_rewardPool).rewardLength();
        for (uint256 i = 0; i < rewardLength; i++) {
            address rewardToken = IConvexRewardPool(_rewardPool).rewards(i);
            if (rewardToken == address(0)) {
                continue;
            }
            uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
            uint256 fee = rewardAmount.mulDiv(feePct, BPS, Math.Rounding.Floor);
            if (fee > 0) {
                IERC20(rewardToken).safeTransfer(treasury, fee);
            }
            _swapToInputTokens(rewardToken, _usdc);
        }
    }
}
