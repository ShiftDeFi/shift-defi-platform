// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Container} from "./Container.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Common} from "./libraries/helpers/Common.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {ICrossChainContainer} from "./interfaces/ICrossChainContainer.sol";
import {IContainer} from "./interfaces/IContainer.sol";

abstract contract CrossChainContainer is Container, ICrossChainContainer {
    using Math for uint256;

    bytes32 internal constant MESSENGER_MANAGER_ROLE = keccak256("MESSENGER_MANAGER_ROLE");
    bytes32 internal constant BRIDGE_ADAPTER_MANAGER_ROLE = keccak256("BRIDGE_ADAPTER_MANAGER_ROLE");

    address public messageRouter;
    address public peerContainer;
    uint256 public remoteChainId;

    uint256 public claimCounter;
    mapping(address => uint256) private _expectedTokenAmounts;
    mapping(address => bool) private _isBridgeAdapterSupported;

    uint256 public constant MAX_BRIDGE_SLIPPAGE = 9000; // 10%
    uint256 public constant BPS = 10000;

    modifier onlyMessageRouter() {
        require(msg.sender == messageRouter, Errors.Unauthorized());
        _;
    }

    function __CrossChainContainer_init(
        ContainerInitParams memory containerParams,
        CrossChainContainerInitParams memory crossChainParams
    ) internal onlyInitializing {
        __Container_init(containerParams);
        _setMessageRouter(crossChainParams.messageRouter);

        require(crossChainParams.remoteChainId > 0, Errors.ZeroAmount());
        remoteChainId = crossChainParams.remoteChainId;
        emit RemoteChainIdUpdated(0, crossChainParams.remoteChainId);
    }

    // ---- Messaging logic ----

    /// @inheritdoc ICrossChainContainer
    function setMessageRouter(address newMessageRouter) external onlyRole(MESSENGER_MANAGER_ROLE) {
        _setMessageRouter(newMessageRouter);
    }

    /// @inheritdoc ICrossChainContainer
    function setPeerContainer(address newPeerContainer) external onlyRole(MESSENGER_MANAGER_ROLE) {
        address previousPeerContainer = peerContainer;
        require(previousPeerContainer == address(0), PeerContainerAlreadySet());
        require(newPeerContainer != address(0), Errors.ZeroAddress());
        peerContainer = newPeerContainer;
        emit PeerContainerUpdated(previousPeerContainer, newPeerContainer);
    }

    function _setMessageRouter(address newMessageRouter) internal {
        require(newMessageRouter != address(0), Errors.ZeroAddress());
        address previousMessageRouter = messageRouter;
        messageRouter = newMessageRouter;
        emit MessageRouterUpdated(previousMessageRouter, newMessageRouter);
    }

    function _processExpectedTokens(address[] memory tokens, uint256[] memory amounts) internal {
        uint256 length = tokens.length;

        require(length == amounts.length, Errors.ArrayLengthMismatch());

        uint256 claimCounterCached = claimCounter;

        for (uint256 i = 0; i < length; i++) {
            require(_isTokenWhitelisted(tokens[i]), NotWhitelistedToken(tokens[i]));

            uint256 expectedAmount = Common.fromUnifiedDecimalsUint8(tokens[i], amounts[i]);
            require(expectedAmount > 0, Errors.ZeroAmount());

            uint256 previousExpectedAmount = _expectedTokenAmounts[tokens[i]];

            if (previousExpectedAmount == 0) {
                claimCounterCached += 1;
            }
            _expectedTokenAmounts[tokens[i]] = previousExpectedAmount + expectedAmount;
        }

        claimCounter = claimCounterCached;
    }

    // ---- Bridge logic ----

    /// @inheritdoc ICrossChainContainer
    function setBridgeAdapter(address bridgeAdapter, bool isSupported) external onlyRole(BRIDGE_ADAPTER_MANAGER_ROLE) {
        require(bridgeAdapter != address(0), Errors.ZeroAddress());
        require(_isBridgeAdapterSupported[bridgeAdapter] != isSupported, SameBridgeAdapterStatus());

        _isBridgeAdapterSupported[bridgeAdapter] = isSupported;
        emit BridgeAdapterUpdated(bridgeAdapter, isSupported);
    }

    /// @inheritdoc ICrossChainContainer
    function isBridgeAdapterSupported(address bridgeAdapter) external view returns (bool) {
        return _isBridgeAdapterSupported[bridgeAdapter];
    }

    function _claimExpectedToken(address bridgeAdapter, address token) internal {
        uint256 claimCounterCached = claimCounter;
        require(claimCounterCached > 0, NotExpectingTokens());
        _validateBridgeAdapter(bridgeAdapter);
        _validateClaimableToken(token);

        uint256 expectedAmount = _expectedTokenAmounts[token];

        _expectedTokenAmounts[token] = 0;
        claimCounter = claimCounterCached - 1;

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IBridgeAdapter(bridgeAdapter).claim(token);
        uint256 amountReceived = IERC20(token).balanceOf(address(this)) - balanceBefore;

        require(amountReceived >= expectedAmount, InsufficientBridgeAmount(expectedAmount, amountReceived));

        emit TokenClaimed(token, amountReceived);
    }

    function _bridgeToken(
        address bridgeAdapter,
        address bridgeTo,
        IBridgeAdapter.BridgeInstruction calldata instruction
    ) internal returns (address, uint256) {
        _validateToken(instruction.token);
        _validateBridgeAdapter(bridgeAdapter);

        BridgeTokenLocalVars memory vars;

        vars.tokenBalanceBefore = IERC20(instruction.token).balanceOf(address(this));
        require(
            vars.tokenBalanceBefore >= instruction.amount,
            Errors.NotEnoughTokens(instruction.token, instruction.amount)
        );
        vars.tokenOnDestinationChain = _getTokenOnDestinationChain(bridgeAdapter, instruction.token);
        vars.minAllowedAmount = instruction.amount.mulDiv(MAX_BRIDGE_SLIPPAGE, BPS);
        require(instruction.minTokenAmount >= vars.minAllowedAmount, Errors.IncorrectAmount());

        _approveTokenToBridgeAdapter(instruction.token, bridgeAdapter, instruction.amount);

        vars.bridgedAmount = IBridgeAdapter(bridgeAdapter).bridge(instruction, bridgeTo);
        vars.tokenBalanceAfter = IERC20(instruction.token).balanceOf(address(this));
        require(vars.tokenBalanceBefore - vars.tokenBalanceAfter >= vars.bridgedAmount, Errors.IncorrectAmount());
        require(
            vars.bridgedAmount > instruction.minTokenAmount,
            BridgeSlippageExceeded(instruction.minTokenAmount, vars.bridgedAmount)
        );
        emit BridgeSent(instruction.token, vars.bridgedAmount, bridgeAdapter, bridgeTo);
        return (vars.tokenOnDestinationChain, Common.toUnifiedDecimalsUint8(instruction.token, vars.bridgedAmount));
    }

    function _getTokenOnDestinationChain(
        address bridgeAdapter,
        address tokenOnSourceChain
    ) private view returns (address) {
        address tokenOnDestinationChain = IBridgeAdapter(bridgeAdapter).bridgePaths(tokenOnSourceChain, remoteChainId);
        require(tokenOnDestinationChain != address(0), Errors.ZeroAddress());
        return tokenOnDestinationChain;
    }

    function _validateBridgeAdapter(address bridgeAdapter) internal view {
        require(bridgeAdapter != address(0), Errors.ZeroAddress());
        require(_isBridgeAdapterSupported[bridgeAdapter], BridgeAdapterNotSupported());
    }

    function _validateClaimableToken(address token) internal view {
        require(_isTokenWhitelisted(token), IContainer.NotWhitelistedToken(token));
        require(_expectedTokenAmounts[token] > 0, TokenNotExpected());
    }

    function _approveTokenToBridgeAdapter(address token, address bridgeAdapter, uint256 amount) internal {
        _validateBridgeAdapter(bridgeAdapter);
        require(token != address(0), Errors.ZeroAddress());
        if (IERC20(token).allowance(address(this), bridgeAdapter) < amount) {
            IERC20(token).approve(bridgeAdapter, amount);
        }
    }
}
