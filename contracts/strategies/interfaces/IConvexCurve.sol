// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IConvexCurve {
    struct CurveStableNGNavLocalVars {
        uint256 curveTotalSupply;
        uint256 token0OwedByStrategy;
        uint256 token1OwedByStrategy;
        uint256 token0AmountInNotion;
        uint256 token1AmountInNotion;
        uint256[] totalUnderlyingTokensInPool;
    }

    error ConvexPoolShutdowned(uint256 convexPoolId);
    error NotEnoughLiquidity();
}
