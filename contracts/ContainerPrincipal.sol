// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {CrossChainContainer} from "./CrossChainContainer.sol";
import {ICrossChainContainer} from "./interfaces/ICrossChainContainer.sol";
import {IContainerPrincipal} from "./interfaces/IContainerPrincipal.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {IMessageRouter} from "./interfaces/IMessageRouter.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Codec} from "./libraries/Codec.sol";

contract ContainerPrincipal is CrossChainContainer, IContainerPrincipal {
    using SafeERC20 for IERC20;

    ContainerPrincipalStatus public status;
    uint256 public nav0;
    uint256 public nav1;
    uint256 public registeredWithdrawShareAmount; // container's share for withdraw

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ContainerInitParams memory containerParams,
        CrossChainContainerInitParams memory crossChainParams
    ) public initializer {
        __CrossChainContainer_init(containerParams, crossChainParams);
        IERC20(notion).approve(vault, type(uint256).max);
    }

    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Principal;
    }

    // ---- Container Principal logic ----

    /// @inheritdoc IContainerPrincipal
    function registerDepositRequest(uint256 amount) external nonReentrant onlyVault {
        require(status == ContainerPrincipalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerPrincipalStatus.DepositRequestRegistered;
        IERC20(notion).safeTransferFrom(vault, address(this), amount);

        emit DepositRequestRegistered(amount);
    }

    /// @inheritdoc IContainerPrincipal
    function registerWithdrawRequest(uint256 amount) external onlyVault {
        require(status == ContainerPrincipalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerPrincipalStatus.WithdrawalRequestRegistered;
        registeredWithdrawShareAmount = amount;

        emit WithdrawalRequestRegistered(amount);
    }

    /// @inheritdoc IContainerPrincipal
    function sendDepositRequest(
        MessageInstruction memory messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable nonReentrant onlyRole(OPERATOR_ROLE) {
        require(status == ContainerPrincipalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());

        uint256 bridgeInstructionsLength = bridgeInstructions.length;
        require(bridgeInstructionsLength > 0, Errors.ZeroAmount());
        require(bridgeAdapters.length == bridgeInstructionsLength, Errors.ArrayLengthMismatch());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());
        require(remoteChainId > 0, RemoteChainIdNotSet());
        address peerContainerCached = peerContainer;
        require(peerContainerCached != address(0), PeerContainerNotSet());

        status = ContainerPrincipalStatus.DepositRequestSent;

        SendDepositRequestLocalVars memory vars;

        vars.tokens = new address[](bridgeInstructionsLength);
        vars.minAmounts = new uint256[](bridgeInstructionsLength);

        for (uint256 i = 0; i < bridgeInstructionsLength; ++i) {
            (vars.tokens[i], vars.minAmounts[i]) = _bridgeToken(
                bridgeAdapters[i],
                peerContainerCached,
                bridgeInstructions[i]
            );
        }

        require(_validateWhitelistedTokensBeforeReport(false, true), WhitelistedTokensOnBalance());

        IMessageRouter(messageRouter).send{value: msg.value}(
            peerContainerCached,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                adapterParameters: messageInstruction.parameters,
                chainTo: remoteChainId,
                message: Codec.encode(Codec.DepositRequest({tokens: vars.tokens, amounts: vars.minAmounts}))
            })
        );

        emit DepositRequestSent();
    }

    /// @inheritdoc IContainerPrincipal
    function sendWithdrawRequest(
        MessageInstruction memory messageInstruction
    ) external payable nonReentrant onlyRole(OPERATOR_ROLE) {
        require(status == ContainerPrincipalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        require(remoteChainId > 0, RemoteChainIdNotSet());
        address peerContainerCached = peerContainer;
        require(peerContainerCached != address(0), PeerContainerNotSet());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());

        uint256 registeredWithdrawShareAmountCached = registeredWithdrawShareAmount;
        require(registeredWithdrawShareAmountCached > 0, Errors.ZeroAmount());

        status = ContainerPrincipalStatus.WithdrawalRequestSent;

        IMessageRouter(messageRouter).send{value: msg.value}(
            peerContainerCached,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                adapterParameters: messageInstruction.parameters,
                chainTo: remoteChainId,
                message: Codec.encode(Codec.WithdrawalRequest({share: registeredWithdrawShareAmountCached}))
            })
        );

        emit WithdrawalRequestSent(registeredWithdrawShareAmountCached);
    }

    /// @inheritdoc IContainerPrincipal
    function reportDeposit() external payable nonReentrant onlyRole(OPERATOR_ROLE) {
        require(
            status == ContainerPrincipalStatus.BridgeClaimed ||
                status == ContainerPrincipalStatus.DepositResponseReceived,
            Errors.IncorrectContainerStatus()
        );
        require(registeredWithdrawShareAmount == 0, Errors.NonZeroAmount());
        require(claimCounter == 0, UnclaimedTokens());
        require(_validateWhitelistedTokensBeforeReport(true, true), WhitelistedTokensOnBalance());

        ReportDepositLocalVars memory vars;
        vars.nav0 = nav0;
        vars.nav1 = nav1;
        vars.remainder = IERC20(notion).balanceOf(address(this));

        status = ContainerPrincipalStatus.Idle;

        IVault(vault).reportDeposit(IVault.ContainerReport({nav0: vars.nav0, nav1: vars.nav1}), vars.remainder);

        emit DepositReported(vars.nav0, vars.nav1, vars.remainder);
    }

    /// @inheritdoc IContainerPrincipal
    function reportWithdrawal() external payable nonReentrant onlyRole(OPERATOR_ROLE) {
        require(status == ContainerPrincipalStatus.BridgeClaimed, Errors.IncorrectContainerStatus());
        require(registeredWithdrawShareAmount > 0, Errors.ZeroAmount());
        require(claimCounter == 0, UnclaimedTokens());
        require(_hasOnlyNotionToken(), WhitelistedTokensOnBalance());

        status = ContainerPrincipalStatus.Idle;
        registeredWithdrawShareAmount = 0;

        IVault(vault).reportWithdraw(IERC20(notion).balanceOf(address(this)));

        emit WithdrawalReported();
    }

    // ---- Messaging logic ----

    /// @inheritdoc ICrossChainContainer
    function receiveMessage(bytes memory rawMessage) external nonReentrant onlyMessageRouter {
        require(
            status == ContainerPrincipalStatus.DepositRequestSent ||
                status == ContainerPrincipalStatus.WithdrawalRequestSent,
            Errors.IncorrectContainerStatus()
        );

        uint8 messageType = Codec.fetchMessageType(rawMessage);
        if (messageType == Codec.DEPOSIT_RESPONSE_TYPE) {
            Codec.DepositResponse memory response = Codec.decodeDepositResponse(rawMessage);
            nav0 = response.navAH;
            nav1 = response.navAE;
            status = ContainerPrincipalStatus.DepositResponseReceived;
            if (response.tokens.length > 0) {
                _processExpectedTokens(response.tokens, response.amounts);
            }
            emit DepositResponseReceived(claimCounter, nav0, nav1);
            return;
        }

        if (messageType == Codec.WITHDRAWAL_RESPONSE_TYPE) {
            Codec.WithdrawalResponse memory response = Codec.decodeWithdrawalResponse(rawMessage);
            status = ContainerPrincipalStatus.WithdrawalResponseReceived;
            if (response.tokens.length > 0) {
                _processExpectedTokens(response.tokens, response.amounts);
            }
            emit WithdrawalResponseReceived(claimCounter);
            return;
        }

        revert Codec.WrongMessageType(messageType);
    }

    // ---- Bridge logic ----

    /// @inheritdoc IContainerPrincipal
    function claim(address bridgeAdapter, address token) external nonReentrant onlyRole(OPERATOR_ROLE) {
        require(
            status == ContainerPrincipalStatus.DepositResponseReceived ||
                status == ContainerPrincipalStatus.WithdrawalResponseReceived,
            Errors.IncorrectContainerStatus()
        );

        _claimExpectedToken(bridgeAdapter, token);

        if (claimCounter == 0) {
            status = ContainerPrincipalStatus.BridgeClaimed;
        }
    }

    /// @inheritdoc IContainerPrincipal
    function claimMultiple(
        address[] calldata bridgeAdapters,
        address[] calldata tokens
    ) external nonReentrant onlyRole(OPERATOR_ROLE) {
        require(
            status == ContainerPrincipalStatus.DepositResponseReceived ||
                status == ContainerPrincipalStatus.WithdrawalResponseReceived,
            Errors.IncorrectContainerStatus()
        );

        uint256 length = bridgeAdapters.length;
        require(length == tokens.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; i++) {
            _claimExpectedToken(bridgeAdapters[i], tokens[i]);
        }

        if (claimCounter == 0) {
            status = ContainerPrincipalStatus.BridgeClaimed;
        }
    }
}
