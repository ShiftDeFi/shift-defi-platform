// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Container, ContainerInitParams} from "./Container.sol";
import {StrategyContainer} from "./StrategyContainer.sol";
import {IContainerLocal} from "./interfaces/IContainerLocal.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IVault} from "./interfaces/IVault.sol";

contract ContainerLocal is StrategyContainer, IContainerLocal {
    using SafeERC20 for IERC20;

    ContainerLocalStatus public status;
    uint256 public registeredWithdrawShareAmount;

    constructor() {
        _disableInitializers();
    }

    function initialize(ContainerInitParams memory containerParams) public initializer {
        __Container_init(containerParams);
        __StrategyContainer_init();
        IERC20(notion).approve(vault, type(uint256).max);
    }

    // ---- Container logic ----

    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Local;
    }

    function _updateStatus(ContainerLocalStatus newStatus) private {
        ContainerLocalStatus previousStatus = status;
        status = newStatus;
        emit StatusUpdated(previousStatus, newStatus);
    }

    // ---- Vault interaction ----

    function registerDepositRequest(uint256 amount) external onlyVault {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        _updateStatus(ContainerLocalStatus.DepositRequestRegistered);
        IERC20(notion).safeTransferFrom(vault, address(this), amount);
    }

    function registerWithdrawRequest(uint256 amount) external onlyVault {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        _updateStatus(ContainerLocalStatus.WithdrawalRequestRegistered);
        registeredWithdrawShareAmount = amount;
    }

    function reportDeposit() external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.AllStrategiesEntered, Errors.IncorrectContainerStatus());
        _checkIfHarvestsAreUpToDate();

        require(_hasOnlyNotionToken(), WhitelistedTokensOnBalance());

        (uint256 nav0, uint256 nav1) = _getTotalNavs();

        _strategyEnterBitmask = 0;
        _strategyHarvestBitmask = 0;

        _updateStatus(ContainerLocalStatus.Idle);

        IVault(vault).reportDeposit(
            IVault.ContainerReport({nav0: nav0, nav1: nav1}),
            IERC20(notion).balanceOf(address(this))
        );
    }

    function reportWithdraw() external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.AllStrategiesExited, Errors.IncorrectContainerStatus());

        registeredWithdrawShareAmount = 0;
        _strategyExitBitmask = 0;
        require(_hasOnlyNotionToken(), WhitelistedTokensOnBalance());
        _updateStatus(ContainerLocalStatus.Idle);
        IVault(vault).reportWithdraw(IERC20(notion).balanceOf(address(this)));
    }

    // ---- Strategy interaction ----

    function enterStrategy(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());
        _enterStrategy(strategy, inputAmounts, minNavDelta);

        if (_allStrategiesEntered()) {
            _updateStatus(ContainerLocalStatus.AllStrategiesEntered);
            emit AllStrategiesEntered();
        }
    }

    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 length = strategies.length;
        require(length == inputAmounts.length, Errors.ArrayLengthMismatch());
        require(length == minNavDelta.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            _enterStrategy(strategies[i], inputAmounts[i], minNavDelta[i]);
        }

        if (_allStrategiesEntered()) {
            _updateStatus(ContainerLocalStatus.AllStrategiesEntered);
            emit AllStrategiesEntered();
        }
    }

    function exitStrategy(address strategy, uint256 minNavDelta) external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());
        _exitStrategy(strategy, registeredShareAmountCached, minNavDelta);

        if (_allStrategiesExited()) {
            _updateStatus(ContainerLocalStatus.AllStrategiesExited);
            emit AllStrategiesExited();
        }
    }

    function exitStrategyMultiple(
        address[] calldata strategies,
        uint256[] calldata minNavDeltas
    ) external onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 length = strategies.length;
        require(length == minNavDeltas.length, Errors.ArrayLengthMismatch());

        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());

        for (uint256 i = 0; i < length; ++i) {
            _exitStrategy(strategies[i], registeredShareAmountCached, minNavDeltas[i]);
        }

        if (_allStrategiesExited()) {
            _updateStatus(ContainerLocalStatus.AllStrategiesExited);
            emit AllStrategiesExited();
        }
    }
}
