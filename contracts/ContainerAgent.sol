// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {CrossChainContainer} from "./CrossChainContainer.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Codec} from "./libraries/Codec.sol";

import {IContainer} from "./interfaces/IContainer.sol";
import {IStrategyContainer} from "./interfaces/IStrategyContainer.sol";
import {ICrossChainContainer} from "./interfaces/ICrossChainContainer.sol";
import {IContainerAgent} from "./interfaces/IContainerAgent.sol";
import {StrategyContainer} from "./StrategyContainer.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {IMessageRouter} from "./interfaces/IMessageRouter.sol";

contract ContainerAgent is CrossChainContainer, StrategyContainer, IContainerAgent {
    using SafeERC20 for IERC20;

    ContainerAgentStatus public status;
    uint256 public registeredWithdrawShareAmount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ContainerInitParams calldata containerParams,
        CrossChainContainerInitParams calldata crossChainParams,
        address emergencyManager
    ) public initializer {
        _grantRole(EMERGENCY_MANAGER_ROLE, emergencyManager);
        __CrossChainContainer_init(containerParams, crossChainParams);
    }

    // ---- Strategy management logic ----

    /// @inheritdoc IStrategyContainer
    function addStrategy(
        address strategy,
        address[] calldata inputTokens,
        address[] calldata outputTokens
    ) external nonReentrant notResolvingEmergency onlyRole(STRATEGY_MANAGER_ROLE) {
        require(status == ContainerAgentStatus.Idle, Errors.IncorrectContainerStatus());
        _addStrategy(strategy, inputTokens, outputTokens);
    }

    /// @inheritdoc IStrategyContainer
    function removeStrategy(
        address strategy
    ) external nonReentrant notResolvingEmergency onlyRole(STRATEGY_MANAGER_ROLE) {
        require(status == ContainerAgentStatus.Idle, Errors.IncorrectContainerStatus());
        _removeStrategy(strategy);
    }

    // ---- Container Agent logic ----

    /// @inheritdoc IContainerAgent
    function enterStrategy(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.BridgeClaimed, Errors.IncorrectContainerStatus());

        _enterStrategy(strategy, inputAmounts, minNavDelta);

        if (_allStrategiesEntered()) {
            status = ContainerAgentStatus.AllStrategiesEntered;
            emit AllStrategiesEntered();
        }
    }

    /// @inheritdoc IContainerAgent
    function enterStrategyMultiple(
        address[] calldata strategies,
        uint256[][] calldata inputAmounts,
        uint256[] calldata minNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.BridgeClaimed, Errors.IncorrectContainerStatus());

        uint256 length = strategies.length;
        require(length == inputAmounts.length, Errors.ArrayLengthMismatch());
        require(length == minNavDelta.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            _enterStrategy(strategies[i], inputAmounts[i], minNavDelta[i]);
        }

        if (_allStrategiesEntered()) {
            status = ContainerAgentStatus.AllStrategiesEntered;
            emit AllStrategiesEntered();
        }
    }

    /// @inheritdoc IContainerAgent
    function exitStrategy(
        address strategy,
        uint256 minNavDelta
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.WithdrawalRequestReceived, Errors.IncorrectContainerStatus());

        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());
        _exitStrategy(strategy, registeredShareAmountCached, minNavDelta);

        if (_allStrategiesExited()) {
            status = ContainerAgentStatus.AllStrategiesExited;
            emit AllStrategiesExited();
        }
    }

    /// @inheritdoc IContainerAgent
    function exitStrategyMultiple(
        address[] calldata strategies,
        uint256[] calldata minNavDeltas
    ) external nonReentrant notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.WithdrawalRequestReceived, Errors.IncorrectContainerStatus());

        uint256 length = strategies.length;
        require(length == minNavDeltas.length, Errors.ArrayLengthMismatch());

        uint256 registeredShareAmountCached = registeredWithdrawShareAmount;
        require(registeredShareAmountCached > 0, NoSharesRegisteredForExit());

        for (uint256 i = 0; i < length; ++i) {
            _exitStrategy(strategies[i], registeredShareAmountCached, minNavDeltas[i]);
        }

        if (_allStrategiesExited()) {
            status = ContainerAgentStatus.AllStrategiesExited;
            emit AllStrategiesExited();
        }
    }

    /// @inheritdoc IContainerAgent
    function reportDeposit(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.AllStrategiesEntered, Errors.IncorrectContainerStatus());
        require(remoteChainId > 0, RemoteChainIdNotSet());
        require(bridgeAdapters.length == bridgeInstructions.length, Errors.ArrayLengthMismatch());

        ReportDepositLocalVars memory vars;
        vars.peerContainerCached = peerContainer;
        require(vars.peerContainerCached != address(0), PeerContainerNotSet());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());

        _strategyEnterBitmask = 0;
        status = ContainerAgentStatus.Idle;

        vars.tokens = new address[](bridgeInstructions.length);
        vars.minAmounts = new uint256[](bridgeInstructions.length);

        for (uint256 i = 0; i < bridgeInstructions.length; ++i) {
            (vars.tokens[i], vars.minAmounts[i]) = _bridgeToken(
                bridgeAdapters[i],
                vars.peerContainerCached,
                bridgeInstructions[i]
            );
        }

        require(_validateWhitelistedTokensBeforeReport(false, true), WhitelistedTokensOnBalance());

        (vars.nav0, vars.nav1) = getTotalNavs();

        IMessageRouter(messageRouter).send{value: msg.value}(
            vars.peerContainerCached,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                chainTo: remoteChainId,
                adapterParameters: messageInstruction.parameters,
                message: Codec.encode(
                    Codec.DepositResponse({
                        tokens: vars.tokens,
                        amounts: vars.minAmounts,
                        navAH: vars.nav0,
                        navAE: vars.nav1
                    })
                )
            })
        );

        emit DepositReported(vars.nav0, vars.nav1);
    }

    /// @inheritdoc IContainerAgent
    function reportWithdrawal(
        MessageInstruction calldata messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.AllStrategiesExited, Errors.IncorrectContainerStatus());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());
        require(remoteChainId > 0, RemoteChainIdNotSet());
        address peerContainerCached = peerContainer;
        require(peerContainerCached != address(0), PeerContainerNotSet());
        require(bridgeAdapters.length > 0, Errors.ZeroArrayLength());
        require(bridgeAdapters.length == bridgeInstructions.length, Errors.ArrayLengthMismatch());
        uint256 registeredWithdrawShareAmountCached = registeredWithdrawShareAmount;

        _strategyExitBitmask = 0;
        registeredWithdrawShareAmount = 0;

        status = ContainerAgentStatus.Idle;

        address[] memory tokens = new address[](bridgeInstructions.length);
        uint256[] memory minAmounts = new uint256[](bridgeInstructions.length);

        for (uint256 i = 0; i < bridgeInstructions.length; ++i) {
            (tokens[i], minAmounts[i]) = _bridgeToken(bridgeAdapters[i], peerContainerCached, bridgeInstructions[i]);
        }

        require(_validateWhitelistedTokensBeforeReport(false, true), WhitelistedTokensOnBalance());

        IMessageRouter(messageRouter).send{value: msg.value}(
            peerContainerCached,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                chainTo: remoteChainId,
                adapterParameters: messageInstruction.parameters,
                message: Codec.encode(Codec.WithdrawalResponse({tokens: tokens, amounts: minAmounts}))
            })
        );

        emit WithdrawalReported(registeredWithdrawShareAmountCached);
    }

    // ---- Messaging logic ----

    /// @inheritdoc ICrossChainContainer
    function receiveMessage(
        bytes memory rawMessage
    ) external notResolvingEmergency notInReshufflingMode onlyMessageRouter {
        require(status == ContainerAgentStatus.Idle, Errors.IncorrectContainerStatus());

        uint8 messageType = Codec.fetchMessageType(rawMessage);
        if (messageType == Codec.DEPOSIT_REQUEST_TYPE) {
            Codec.DepositRequest memory request = Codec.decodeDepositRequest(rawMessage);
            if (request.tokens.length > 0) {
                _processExpectedTokens(request.tokens, request.amounts);
            }
            status = ContainerAgentStatus.DepositRequestReceived;
            emit DepositRequestReceived(claimCounter);
            return;
        }

        if (messageType == Codec.WITHDRAWAL_REQUEST_TYPE) {
            Codec.WithdrawalRequest memory request = Codec.decodeWithdrawalRequest(rawMessage);
            if (request.share > 0) {
                registeredWithdrawShareAmount = request.share;
                status = ContainerAgentStatus.WithdrawalRequestReceived;
                emit WithdrawalRequestReceived(registeredWithdrawShareAmount);
            }
            return;
        }

        revert Codec.WrongMessageType(messageType);
    }

    // ---- Bridge logic ----

    /// @inheritdoc IContainerAgent
    function claim(
        address bridgeAdapter,
        address token
    ) external nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.DepositRequestReceived, Errors.IncorrectContainerStatus());
        _claimExpectedToken(bridgeAdapter, token);

        if (claimCounter == 0) {
            status = ContainerAgentStatus.BridgeClaimed;
        }
    }

    /// @inheritdoc IContainerAgent
    function claimInReshufflingMode(
        address bridgeAdapter,
        address token
    ) external nonReentrant notResolvingEmergency onlyInReshufflingMode onlyRole(RESHUFFLING_MANAGER_ROLE) {
        _validateBridgeAdapter(bridgeAdapter);
        require(_isTokenWhitelisted(token), NotWhitelistedToken(token));
        IBridgeAdapter(bridgeAdapter).claim(token);
    }

    /// @inheritdoc IContainerAgent
    function claimMultiple(
        address[] calldata bridgeAdapters,
        address[] calldata tokens
    ) external nonReentrant notResolvingEmergency notInReshufflingMode onlyRole(OPERATOR_ROLE) {
        require(status == ContainerAgentStatus.DepositRequestReceived, Errors.IncorrectContainerStatus());

        uint256 length = bridgeAdapters.length;
        require(length == tokens.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; i++) {
            _claimExpectedToken(bridgeAdapters[i], tokens[i]);
        }

        if (claimCounter == 0) {
            status = ContainerAgentStatus.BridgeClaimed;
        }
    }

    /// @inheritdoc IContainerAgent
    function withdrawToReshufflingGateway(
        address[] memory bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata instructions
    ) external nonReentrant notResolvingEmergency onlyInReshufflingMode onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(bridgeAdapters.length == instructions.length, Errors.ArrayLengthMismatch());
        require(bridgeAdapters.length > 0, Errors.ZeroArrayLength());

        for (uint256 i = 0; i < bridgeAdapters.length; ++i) {
            _validateBridgeAdapter(bridgeAdapters[i]);
        }

        address bridgeCollectorCached = _bridgeCollector;
        require(bridgeCollectorCached != address(0), Errors.ZeroAddress());

        uint256 length = instructions.length;
        for (uint256 i = 0; i < length; ++i) {
            _bridgeToken(bridgeAdapters[i], bridgeCollectorCached, instructions[i]);
        }
    }

    /// @inheritdoc IContainer
    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Agent;
    }

    function _getCurrentBatchType() internal view override returns (CurrentBatchType) {
        ContainerAgentStatus statusCached = status;
        if (statusCached == ContainerAgentStatus.Idle) {
            return CurrentBatchType.NoBatch;
        }

        if (
            statusCached == ContainerAgentStatus.WithdrawalRequestReceived ||
            statusCached == ContainerAgentStatus.AllStrategiesExited
        ) {
            return CurrentBatchType.WithdrawBatch;
        }

        if (
            statusCached == ContainerAgentStatus.DepositRequestReceived ||
            statusCached == ContainerAgentStatus.BridgeClaimed ||
            statusCached == ContainerAgentStatus.AllStrategiesEntered
        ) {
            return CurrentBatchType.DepositBatch;
        }

        revert Errors.IncorrectContainerStatus();
    }
}
