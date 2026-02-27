// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {CrossChainContainer} from "contracts/CrossChainContainer.sol";

contract MockCrossChainContainer is CrossChainContainer {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IContainer.ContainerInitParams memory containerParams,
        ICrossChainContainer.CrossChainContainerInitParams memory crossChainParams
    ) public initializer {
        super.__CrossChainContainer_init(containerParams, crossChainParams);
    }

    function containerType() external pure override returns (ContainerType) {
        /// @dev Irrelevant for CrossChainContainer
        return ContainerType.Agent;
    }

    function processExpectedTokens(address[] memory tokens, uint256[] memory amounts) external {
        _processExpectedTokens(tokens, amounts);
    }

    function claimExpectedToken(address bridgeAdapter, address token) external {
        _claimExpectedToken(bridgeAdapter, token);
    }

    function bridgeToken(
        address bridgeAdapter,
        address bridgeTo,
        IBridgeAdapter.BridgeInstruction calldata instruction
    ) external returns (address, uint256) {
        return _bridgeToken(bridgeAdapter, bridgeTo, instruction);
    }

    function validateBridgeAdapter(address bridgeAdapter) external view {
        _validateBridgeAdapter(bridgeAdapter);
    }

    function validateClaimableToken(address token) external view {
        _validateClaimableToken(token);
    }

    function approveTokenToBridgeAdapter(address token, address bridgeAdapter, uint256 amount) external {
        _approveTokenToBridgeAdapter(token, bridgeAdapter, amount);
    }

    function receiveMessage(bytes memory rawMessage) external {}
}
