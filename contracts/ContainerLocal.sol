// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Container} from "./Container.sol";
import {StrategyContainer} from "./StrategyContainer.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {IStrategyContainer} from "./interfaces/IStrategyContainer.sol";
import {IContainerLocal} from "./interfaces/IContainerLocal.sol";
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
        IERC20(notion).approve(vault, type(uint256).max);
    }

    // ---- Container logic ----

    /// @inheritdoc IContainer
    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Local;
    }

    // ---- Vault interaction ----

    /// @inheritdoc IContainerLocal
    function registerDepositRequest(
        uint256 amount
    ) external nonReentrant notResolvingEmergency notInReshufflingMode onlyVault {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerLocalStatus.DepositRequestRegistered;
        IERC20(notion).safeTransferFrom(vault, address(this), amount);
    }

    /// @inheritdoc IContainerLocal
    function registerWithdrawRequest(
        uint256 amount
    ) external nonReentrant notResolvingEmergency notInReshufflingMode onlyVault {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerLocalStatus.WithdrawalRequestRegistered;
        registeredWithdrawShareAmount = amount;
    }

    /// @inheritdoc IContainerLocal
    function reportDeposit() external nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.AllStrategiesEntered, Errors.IncorrectContainerStatus());

        require(_validateWhitelistedTokensBeforeReport(true, true), WhitelistedTokensOnBalance());

        (uint256 nav0, uint256 nav1) = getTotalNavs();

        status = ContainerLocalStatus.Idle;
        _strategyEnterBitmask = 0;

        IVault(vault).reportDeposit(
            IVault.ContainerReport({nav0: nav0, nav1: nav1}),
            IERC20(notion).balanceOf(address(this))
        );
    }

    /// @inheritdoc IContainerLocal
    function reportWithdraw() external nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.AllStrategiesExited, Errors.IncorrectContainerStatus());

        status = ContainerLocalStatus.Idle;
        registeredWithdrawShareAmount = 0;
        _strategyExitBitmask = 0;
        require(_hasOnlyNotionToken(), WhitelistedTokensOnBalance());
        IVault(vault).reportWithdraw(IERC20(notion).balanceOf(address(this)));
    }

    // ---- Strategy management logic ----

    /// @inheritdoc IStrategyContainer
    function addStrategy(
        address strategy,
        address[] calldata inputTokens,
        address[] calldata outputTokens
    ) external nonReentrant notResolvingEmergency onlyRole(STRATEGY_MANAGER_ROLE) {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        _addStrategy(strategy, inputTokens, outputTokens);
    }

    /// @inheritdoc IStrategyContainer
    function removeStrategy(
        address strategy
    ) external nonReentrant notResolvingEmergency onlyRole(STRATEGY_MANAGER_ROLE) {
        require(status == ContainerLocalStatus.Idle, Errors.IncorrectContainerStatus());
        _removeStrategy(strategy);
    }

    // ---- Enter strategy logic ----

    /// @inheritdoc IContainerLocal
    function enterStrategy(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());
        _enterStrategy(strategy, inputAmounts, minNavDelta);

        if (_allStrategiesEntered()) {
            status = ContainerLocalStatus.AllStrategiesEntered;
            emit AllStrategiesEntered();
        }
    }

    /// @inheritdoc IContainerLocal
    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 length = strategies.length;
        require(length == inputAmounts.length, Errors.ArrayLengthMismatch());
        require(length == minNavDelta.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            _enterStrategy(strategies[i], inputAmounts[i], minNavDelta[i]);
        }

        if (_allStrategiesEntered()) {
            status = ContainerLocalStatus.AllStrategiesEntered;
            emit AllStrategiesEntered();
        }
    }

    // ---- Exit strategy logic ----

    /// @inheritdoc IContainerLocal
    function exitStrategy(
        address strategy,
        uint256 maxNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());
        _exitStrategy(strategy, registeredShareAmountCached, maxNavDelta);

        if (_allStrategiesExited()) {
            status = ContainerLocalStatus.AllStrategiesExited;
            emit AllStrategiesExited();
        }
    }

    /// @inheritdoc IContainerLocal
    function exitStrategyMultiple(
        address[] calldata strategies,
        uint256[] calldata maxNavDeltas
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerLocalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        uint256 length = strategies.length;
        require(length == maxNavDeltas.length, Errors.ArrayLengthMismatch());

        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());

        for (uint256 i = 0; i < length; ++i) {
            _exitStrategy(strategies[i], registeredShareAmountCached, maxNavDeltas[i]);
        }

        if (_allStrategiesExited()) {
            status = ContainerLocalStatus.AllStrategiesExited;
            emit AllStrategiesExited();
        }
    }

    function _getCurrentBatchType() internal view override returns (CurrentBatchType) {
        ContainerLocalStatus statusCached = status;
        if (statusCached == ContainerLocalStatus.Idle) {
            return CurrentBatchType.NoBatch;
        }

        if (
            statusCached == ContainerLocalStatus.DepositRequestRegistered ||
            statusCached == ContainerLocalStatus.AllStrategiesEntered
        ) {
            return CurrentBatchType.DepositBatch;
        }

        if (
            statusCached == ContainerLocalStatus.WithdrawalRequestRegistered ||
            statusCached == ContainerLocalStatus.AllStrategiesExited
        ) {
            return CurrentBatchType.WithdrawBatch;
        }

        revert Errors.IncorrectContainerStatus();
    }

    /// @inheritdoc IContainerLocal
    function withdrawToReshufflingGateway(
        address[] memory tokens,
        uint256[] memory amounts
    ) external nonReentrant notResolvingEmergency onlyInReshufflingMode onlyRole(RESHUFFLING_MANAGER_ROLE) {
        uint256 length = tokens.length;
        require(tokens.length == amounts.length, Errors.ArrayLengthMismatch());
        require(tokens.length > 0, Errors.ZeroArrayLength());

        address bridgeCollectorCached = _bridgeCollector;
        require(bridgeCollectorCached != address(0), Errors.ZeroAddress());

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            uint256 amount = amounts[i];

            require(_isTokenWhitelisted(token), NotWhitelistedToken(token));
            if (amount > 0) {
                IERC20(token).safeTransfer(bridgeCollectorCached, amount);
            }
        }
    }
}
