// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICrossChainContainer {
    // ---- Structs ----

    struct MessageInstruction {
        address adapter;
        bytes parameters;
    }

    struct BridgeTokenLocalVars {
        address tokenOnDestinationChain;
        uint256 minAllowedAmount;
        uint256 tokenBalanceBefore;
        uint256 tokenBalanceAfter;
        uint256 bridgedAmount;
    }

    // ---- Events ----

    event MessageRouterUpdated(address previousMessageRouter, address newMessageRouter);
    event TokenClaimed(address token, uint256 amount);
    event BridgeAdapterUpdated(address bridgeAdapter, bool isSupported);
    event PeerContainerUpdated(address previousPeerContainer, address newPeerContainer);
    event RemoteChainIdUpdated(uint256 previousRemoteChainId, uint256 newRemoteChainId);
    event BridgeSent(address token, uint256 amount, address bridgeAdapter, address bridgeTo);

    // ---- Errors ----

    error TokenNotExpected();
    error UnclaimedTokens();
    error InsufficientBridgeAmount(uint256 expected, uint256 received);
    error NotExpectingTokens();
    error BridgeAdapterNotSupported();
    error SameBridgeAdapterStatus();
    error PeerContainerAlreadySet();
    error RemoteChainIdAlreadySet();
    error InvalidDecimals();
    error BridgeSlippageExceeded(uint256 expected, uint256 received);
    error RemoteChainIdNotSet();

    // ---- Functions ----

    function setMessageRouter(address newMessageRouter) external;

    function setPeerContainer(address newPeerContainer) external;

    function setBridgeAdapter(address bridgeAdapter, bool isSupported) external;

    function peerContainer() external view returns (address);

    function remoteChainId() external view returns (uint256);
}
