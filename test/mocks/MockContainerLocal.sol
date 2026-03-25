// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";

contract MockContainerLocal is IContainerLocal {
    ContainerLocalStatus public _status;

    function status() external view returns (ContainerLocalStatus) {
        return _status;
    }

    function setStatus(ContainerLocalStatus newStatus) external {
        _status = newStatus;
    }

    function removeStrategy(address) external pure {}

    function registeredWithdrawShareAmount() external pure returns (uint256) {
        return 0;
    }

    function registerDepositRequest(uint256 amount) external {}

    function registerWithdrawRequest(uint256 amount) external {}

    function reportDeposit() external {}

    function reportWithdraw() external {}

    function withdrawToReshufflingGateway(address[] memory tokens, uint256[] memory amounts) external {}

    function addStrategy(address strategy, address[] calldata inputTokens, address[] calldata outputTokens) external {}

    function enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external {}

    function exitStrategy(address strategy) external {}

    function containerType() external pure returns (ContainerType) {
        return ContainerType.Local;
    }

    function isTokenWhitelisted(address) external pure returns (bool) {
        return true;
    }

    function whitelistToken(address) external pure {}

    function blacklistToken(address) external pure {}

    function setWhitelistedTokenDustThreshold(address, uint256) external pure {}

    function setSwapRouter(address) external pure {}

    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata) external override {}

    function pause() external pure {}

    function unpause() external pure {}

    function setMessageRouter(address) external pure {}

    function peerContainer() external pure returns (address) {
        return address(0);
    }

    function getStrategies() external pure returns (address[] memory) {
        return new address[](0);
    }

    function getStrategiesNumber() external pure returns (uint256) {
        return 0;
    }

    function isStrategy(address) external pure returns (bool) {
        return false;
    }

    function vault() external pure returns (address) {
        return address(0);
    }

    function notion() external pure returns (address) {
        return address(0);
    }

    function swapRouter() external pure returns (address) {
        return address(0);
    }

    function treasury() external pure returns (address) {
        return address(0);
    }

    function startEmergencyResolution() external pure {}

    function resolveEmergency() external pure {}

    function priceOracle() external pure returns (address) {
        return address(0);
    }

    function feePct() external pure returns (uint256) {
        return 0;
    }

    function setReshufflingGateway(address) external pure {}

    function setTreasury(address) external pure {}

    function setFeePct(uint256) external pure {}

    function setPriceOracle(address) external pure {}

    function setStrategyOutputTokens(address, address[] calldata) external pure {}

    function setStrategyInputTokens(address, address[] calldata) external pure {}

    function getTotalNavs() external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function isStrategyNavUnresolved(address) external pure returns (bool) {
        return false;
    }

    function enterInReshufflingMode(address, uint256[] calldata, uint256) external pure {}

    function exitInReshufflingMode(address, uint256, uint256) external pure {}

    function completeEmergencyResolution() external pure {}

    function completeDepositRequest() external pure {}

    function disableReshufflingMode() external pure {}

    function enableReshufflingMode() external pure {}

    function exitStrategyMultiple(address[] calldata, uint256[] calldata) external pure {}

    function enterStrategyMultiple(address[] calldata, uint256[][] calldata, uint256[] calldata) external pure {}

    function exitStrategy(address, uint256) external pure {}

    function resolveStrategyNav(uint256) external {}

    function prepareLiquidityInReshufflingMode(ISwapRouter.SwapInstruction[] calldata) external pure {}
}
