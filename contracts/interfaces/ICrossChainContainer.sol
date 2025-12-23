// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IContainer} from "./IContainer.sol";

interface ICrossChainContainer is IContainer {
    // ---- Structs ----

    struct CrossChainContainerInitParams {
        address messageRouter;
        uint256 remoteChainId;
    }

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
    error PeerContainerNotSet();

    // ---- Functions ----

    /**
     * @notice Returns the message router address.
     * @return The address of the message router contract
     */
    function messageRouter() external view returns (address);

    /**
     * @notice Returns the peer container address on the remote chain.
     * @return The address of the peer container contract
     */
    function peerContainer() external view returns (address);

    /**
     * @notice Returns the remote chain ID.
     * @return The chain ID of the remote chain
     */
    function remoteChainId() external view returns (uint256);

    /**
     * @notice Returns the current claim counter.
     * @return The current value of the claim counter
     */
    function claimCounter() external view returns (uint256);

    /**
     * @notice Sets the message router address.
     * @dev Can only be called by accounts with appropriate role.
     * @param newMessageRouter The address of the new message router contract
     */
    function setMessageRouter(address newMessageRouter) external;

    /**
     * @notice Sets the peer container address.
     * @dev Can only be called by accounts with appropriate role. Can only be set once.
     * @param newPeerContainer The address of the peer container on the remote chain
     */
    function setPeerContainer(address newPeerContainer) external;

    /**
     * @notice Receives and processes a cross-chain message.
     * @dev Can only be called by the message router.
     * @param rawMessage The raw message bytes received from the message router
     */
    function receiveMessage(bytes memory rawMessage) external;

    /**
     * @notice Sets whether a bridge adapter is supported.
     * @dev Can only be called by accounts with appropriate role.
     * @param bridgeAdapter The address of the bridge adapter
     * @param isSupported True to enable the bridge adapter, false to disable
     */
    function setBridgeAdapter(address bridgeAdapter, bool isSupported) external;

    /**
     * @notice Checks if a bridge adapter is supported.
     * @param bridgeAdapter The address of the bridge adapter to check
     * @return True if the bridge adapter is supported, false otherwise
     */
    function isBridgeAdapterSupported(address bridgeAdapter) external view returns (bool);
}
