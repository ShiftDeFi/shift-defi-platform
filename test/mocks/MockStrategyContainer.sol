// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {StrategyContainer} from "contracts/StrategyContainer.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableAddressSetExtended} from "contracts/libraries/helpers/EnumerableAddressSetExtended.sol";

contract MockStrategyContainer is StrategyContainer {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;

    IStrategyContainer.CurrentBatchType public currentBatchType;

    function initialize(
        IContainer.ContainerInitParams memory containerParams,
        IStrategyContainer.RoleAddresses calldata roleAddresses,
        address _reshufflingGateway,
        address _treasury,
        uint256 _feePct,
        address _priceOracle
    ) public initializer {
        __Container_init(containerParams);
        __StrategyContainer_init(roleAddresses, _reshufflingGateway, _treasury, _feePct, _priceOracle);
    }

    function craftCurrentBatchType(IStrategyContainer.CurrentBatchType _currentBatchType) external {
        currentBatchType = _currentBatchType;
    }

    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Local;
    }

    function addStrategy(address strategy, address[] calldata inputTokens, address[] calldata outputTokens) external {
        _addStrategy(strategy, inputTokens, outputTokens);
    }

    function removeStrategy(address strategy) external {
        _removeStrategy(strategy);
    }

    function enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) external {
        _enterStrategy(strategy, inputAmounts, minNavDelta);
    }

    function allStrategiesEntered() external view returns (bool) {
        return _allStrategiesEntered();
    }

    function exitStrategy(address strategy, uint256 share, uint256 maxNavDelta) external {
        _exitStrategy(strategy, share, maxNavDelta);
    }

    function allStrategiesExited() external view returns (bool) {
        return _allStrategiesExited();
    }

    function _getCurrentBatchType() internal view override returns (CurrentBatchType) {
        return currentBatchType;
    }

    function getStrategyUnresolvedNavBitmask() external view returns (uint256) {
        return _strategyUnresolvedNavBitmask;
    }

    function validateEnterStrategy(address strategy) external view returns (bool) {
        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        uint256 strategyMask = 1 << strategyIndex;

        if (_strategyEnterBitmask & strategyMask == 0) {
            return false;
        }

        uint256 navDelta = _strategyNav1[strategy] - _strategyNav0[strategy];
        if (navDelta == 0) {
            return false;
        }

        return true;
    }

    function validateExitStrategy(address strategy) external view returns (bool) {
        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        uint256 strategyMask = 1 << strategyIndex;

        if (_strategyExitBitmask & strategyMask == 0) {
            return false;
        }

        return true;
    }
}
