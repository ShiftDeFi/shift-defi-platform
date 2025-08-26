// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {CrossChainContainer, CrossChainContainerInitParams, ContainerInitParams} from "./CrossChainContainer.sol";
import {IContainerPrincipal} from "./interfaces/IContainerPrincipal.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {IMessageReceiver} from "./interfaces/IMessageReceiver.sol";
import {DepositRequestLib} from "./libraries/DepositRequestLib.sol";
import {IMessageRouter} from "./interfaces/IMessageRouter.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {ContainerMessagePackingLib} from "./libraries/ContainerMessagePackingLib.sol";
import {DepositResponseLib} from "./libraries/DepositResponseLib.sol";
import {WithdrawalRequestLib} from "./libraries/WithdrawalRequestLib.sol";
import {WithdrawalResponseLib} from "./libraries/WithdrawalResponseLib.sol";

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

    function registerDepositRequest(uint256 amount) external onlyVault {
        require(status == ContainerPrincipalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerPrincipalStatus.DepositRequestRegistered;
        IERC20(notion).safeTransferFrom(vault, address(this), amount);

        emit DepositRequestRegistered(amount);
    }

    function registerWithdrawRequest(uint256 amount) external onlyVault {
        require(status == ContainerPrincipalStatus.Idle, Errors.IncorrectContainerStatus());
        require(amount > 0, Errors.ZeroAmount());
        status = ContainerPrincipalStatus.WithdrawalRequestRegistered;
        registeredWithdrawShareAmount = amount;

        emit WithdrawalRequestRegistered(amount);
    }

    function sendDepositRequest(
        MessageInstruction memory messageInstruction,
        address[] calldata bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata bridgeInstructions
    ) external payable onlyRole(OPERATOR_ROLE) nonReentrant {
        require(status == ContainerPrincipalStatus.DepositRequestRegistered, Errors.IncorrectContainerStatus());
        require(bridgeInstructions.length > 0, Errors.ZeroAmount());
        require(bridgeAdapters.length == bridgeInstructions.length, Errors.ArrayLengthMismatch());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());
        require(remoteChainId > 0, Errors.ZeroAmount());

        status = ContainerPrincipalStatus.DepositRequestSent;

        SendDepositRequestLocalVars memory vars;

        vars.tokens = new address[](bridgeInstructions.length);
        vars.minAmounts = new uint256[](bridgeInstructions.length);

        for (uint256 i = 0; i < bridgeInstructions.length; i++) {
            (vars.tokens[i], vars.minAmounts[i]) = _bridgeToken(
                bridgeAdapters[i],
                peerContainer,
                bridgeInstructions[i]
            );
        }

        require(_hasZeroBalanceForAllWhitelistedTokens(false), WhitelistedTokensOnBalance());

        IMessageRouter(messageRouter).send{value: msg.value}(
            peerContainer,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                adapterParameters: messageInstruction.parameters,
                chainTo: remoteChainId,
                message: DepositRequestLib.encode(
                    DepositRequestLib.DepositRequest({tokens: vars.tokens, amounts: vars.minAmounts})
                )
            })
        );

        emit DepositRequestSent();
    }

    function sendWithdrawRequest(
        MessageInstruction memory messageInstruction
    ) external payable onlyRole(OPERATOR_ROLE) nonReentrant {
        require(status == ContainerPrincipalStatus.WithdrawalRequestRegistered, Errors.IncorrectContainerStatus());
        require(remoteChainId > 0, Errors.ZeroAmount());
        require(messageInstruction.adapter != address(0), Errors.ZeroAddress());

        uint256 registeredWithdrawShareAmountCached = registeredWithdrawShareAmount;
        require(registeredWithdrawShareAmountCached > 0, Errors.ZeroAmount());

        status = ContainerPrincipalStatus.WithdrawalRequestSent;

        IMessageRouter(messageRouter).send{value: msg.value}(
            peerContainer,
            IMessageRouter.SendParams({
                adapter: messageInstruction.adapter,
                adapterParameters: messageInstruction.parameters,
                chainTo: remoteChainId,
                message: WithdrawalRequestLib.encode(
                    WithdrawalRequestLib.WithdrawalRequest({share: registeredWithdrawShareAmountCached})
                )
            })
        );

        emit WithdrawalRequestSent(registeredWithdrawShareAmountCached);
    }

    function reportDeposit() external payable onlyRole(OPERATOR_ROLE) nonReentrant {
        require(
            status == ContainerPrincipalStatus.BridgeClaimed ||
                status == ContainerPrincipalStatus.DepositResponseReceived,
            Errors.IncorrectContainerStatus()
        );
        require(registeredWithdrawShareAmount == 0, Errors.NonZeroAmount());
        require(claimCounter == 0, UnclaimedTokens());
        require(_hasOnlyNotionToken(), WhitelistedTokensOnBalance());

        ReportDepositLocalVars memory vars;
        vars.nav0 = nav0;
        vars.nav1 = nav1;
        vars.remainder = IERC20(notion).balanceOf(address(this));

        status = ContainerPrincipalStatus.Idle;

        IVault(vault).reportDeposit(IVault.ContainerReport({nav0: vars.nav0, nav1: vars.nav1}), vars.remainder);

        emit DepositReported(vars.nav0, vars.nav1, vars.remainder);
    }

    function reportWithdrawal() external payable onlyRole(OPERATOR_ROLE) nonReentrant {
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

    function receiveMessage(bytes memory rawMessage) external nonReentrant onlyMessageRouter {
        require(
            status == ContainerPrincipalStatus.DepositRequestSent ||
                status == ContainerPrincipalStatus.WithdrawalRequestSent,
            Errors.IncorrectContainerStatus()
        );

        ContainerMessagePackingLib.ContainerMessage memory message = ContainerMessagePackingLib.decode(rawMessage);
        if (message.type_ == ContainerMessagePackingLib.DEPOSIT_RESPONSE_TYPE) {
            DepositResponseLib.DepositResponse memory response = DepositResponseLib.decode(message.payload);
            nav0 = response.navAH;
            nav1 = response.navAE;
            status = ContainerPrincipalStatus.DepositResponseReceived;
            if (response.tokens.length > 0) {
                _processExpectedTokens(response.tokens, response.amounts);
            }

            emit DepositResponseReceived(claimCounter, nav0, nav1);
            return;
        }

        if (message.type_ == ContainerMessagePackingLib.WITHDRAWAL_RESPONSE_TYPE) {
            WithdrawalResponseLib.WithdrawalResponse memory response = WithdrawalResponseLib.decode(message.payload);
            status = ContainerPrincipalStatus.WithdrawalResponseReceived;
            if (response.tokens.length > 0) {
                _processExpectedTokens(response.tokens, response.amounts);
            }

            emit WithdrawalResponseReceived(claimCounter);
            return;
        }
    }

    // ---- Bridge logic ----

    function claim(address bridgeAdapter, address token) external onlyRole(OPERATOR_ROLE) nonReentrant {
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

    function claimMultiple(
        address[] calldata bridgeAdapters,
        address[] calldata tokens
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
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
