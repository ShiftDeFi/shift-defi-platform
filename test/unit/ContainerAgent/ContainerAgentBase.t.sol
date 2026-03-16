// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {L2Base} from "test/L2Base.t.sol";
import {Utils} from "test/Utils.sol";

contract ContainerAgentBaseTest is L2Base {
    uint256 internal constant MAX_STRATEGIES = 255;
    bytes32 internal constant PEER_CONTAINER_SLOT = bytes32(uint256(7));
    bytes32 internal constant REMOTE_CHAIN_ID_SLOT = bytes32(uint256(8));
    bytes32 internal constant STRATEGY_ENTER_BITMASK_SLOT = bytes32(uint256(16));
    bytes32 internal constant STRATEGY_EXIT_BITMASK_SLOT = bytes32(uint256(17));
    bytes32 internal constant IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT = bytes32(uint256(23));
    bytes32 internal constant REGISTERED_WITHDRAW_SHARE_AMOUNT_SLOT = bytes32(uint256(75));
    uint256 internal constant IS_RESOLVING_EMERGENCY_OFFSET = 8;

    uint256 internal constant DEPOSIT_AMOUNT = 1_000_000 * NOTION_PRECISION;
    uint256 internal constant WITHDRAWN_AMOUNT = 1_000_000 * NOTION_PRECISION;

    function setUp() public virtual override {
        super.setUp();

        containerAgent = _deployContainerAgent();

        vm.startPrank(roles.defaultAdmin);
        AccessControl(address(containerAgent)).grantRole(STRATEGY_MANAGER_ROLE, roles.strategyManager);
        AccessControl(address(containerAgent)).grantRole(RESHUFFLING_MANAGER_ROLE, roles.reshufflingManager);
        AccessControl(address(containerAgent)).grantRole(MESSENGER_MANAGER_ROLE, roles.messengerManager);
        AccessControl(address(containerAgent)).grantRole(BRIDGE_ADAPTER_MANAGER_ROLE, roles.bridgeAdapterManager);
        AccessControl(address(containerAgent)).grantRole(TOKEN_MANAGER_ROLE, roles.tokenManager);
        vm.stopPrank();

        vm.prank(roles.strategyManager);
        containerAgent.setTreasury(treasury);

        vm.prank(roles.messengerManager);
        containerAgent.setPeerContainer(makeAddr("CONTAINER_PRINCIPAL"));

        vm.prank(roles.bridgeAdapterManager);
        containerAgent.setBridgeAdapter(address(bridgeAdapter), true);

        vm.startPrank(roles.governance);
        bridgeAdapter.setSlippageCapPct(MAX_BPS);
        bridgeAdapter.whitelistBridger(address(containerAgent));
        vm.stopPrank();
    }

    function test_ContainerTypeIsAgent() public view {
        assertEq(
            uint256(containerAgent.containerType()),
            uint256(IContainer.ContainerType.Agent),
            "test_ContainerTypeIsAgent: container type mismatch"
        );
    }

    function test_ToggleEmergencyResolutionMode() public {
        _toggleEmergencyResolutionMode(true);
        assertTrue(
            containerAgent.isResolvingEmergency(),
            "test_ToggleEmergencyResolutionMode: should be resolving emergency"
        );
        _toggleEmergencyResolutionMode(false);
        assertFalse(
            containerAgent.isResolvingEmergency(),
            "test_ToggleEmergencyResolutionMode: should not be resolving emergency"
        );
    }

    function test_ToggleReshufflingMode() public {
        _toggleReshufflingMode(true);
        uint256 isReshuffling = uint256(
            vm.load(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT)
        );
        assertTrue((isReshuffling & 1) != 0, "test_ToggleReshufflingMode: reshuffling bit should be set");

        _toggleReshufflingMode(false);
        isReshuffling = uint256(vm.load(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT));
        assertTrue((isReshuffling & 1) == 0, "test_ToggleReshufflingMode: reshuffling bit should be unset");
    }

    function _addStrategyNotionInputOutput() internal returns (address) {
        address strategy = address(_deployMockStrategy());
        uint256 tokenNumber = 1;
        address[] memory inputTokens = new address[](tokenNumber);
        address[] memory outputTokens = new address[](tokenNumber);
        inputTokens[0] = address(notion);
        outputTokens[0] = address(notion);
        vm.prank(roles.strategyManager);
        containerAgent.addStrategy(strategy, inputTokens, outputTokens);
        MockStrategy(strategy).setState(bytes32(uint256(1)), true, true, false, 1);

        return strategy;
    }

    function _getStrategyEnterBitmask() internal view returns (uint256) {
        return uint256(vm.load(address(containerAgent), STRATEGY_ENTER_BITMASK_SLOT));
    }

    function _getStrategyExitBitmask() internal view returns (uint256) {
        return uint256(vm.load(address(containerAgent), STRATEGY_EXIT_BITMASK_SLOT));
    }

    function _setRegisteredWithdrawShareAmount(uint256 amount) internal {
        vm.store(address(containerAgent), REGISTERED_WITHDRAW_SHARE_AMOUNT_SLOT, bytes32(amount));
        assertEq(
            containerAgent.registeredWithdrawShareAmount(),
            amount,
            "_setRegisteredWithdrawShareAmount: amount mismatch"
        );
    }

    function _setRemoteChainId(uint256 remoteChainId) internal {
        vm.store(address(containerAgent), REMOTE_CHAIN_ID_SLOT, bytes32(remoteChainId));
        assertEq(containerAgent.remoteChainId(), remoteChainId, "_setRemoteChainId: remote chain id mismatch");
    }

    function _setPeerContainer(address peerContainer) internal {
        vm.store(address(containerAgent), PEER_CONTAINER_SLOT, bytes32(uint256(uint160(peerContainer))));
        assertEq(containerAgent.peerContainer(), peerContainer, "_setPeerContainer: peer container mismatch");
    }

    function _prepareReportData(
        address[] memory bridgedTokens,
        uint256[] memory bridgedAmounts
    )
        internal
        view
        returns (
            ICrossChainContainer.MessageInstruction memory,
            address[] memory,
            IBridgeAdapter.BridgeInstruction[] memory
        )
    {
        uint256 tokenNumber = bridgedTokens.length;
        require(bridgedAmounts.length == tokenNumber, Errors.ArrayLengthMismatch());
        ICrossChainContainer.MessageInstruction memory messageInstruction = ICrossChainContainer.MessageInstruction({
            adapter: address(messageAdapter),
            parameters: ""
        });

        address[] memory bridgeAdapters = new address[](tokenNumber);
        for (uint256 i = 0; i < tokenNumber; ++i) {
            bridgeAdapters[i] = address(bridgeAdapter);
        }

        IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions = new IBridgeAdapter.BridgeInstruction[](
            tokenNumber
        );
        for (uint256 i = 0; i < tokenNumber; ++i) {
            bridgeInstructions[i] = IBridgeAdapter.BridgeInstruction({
                chainTo: REMOTE_CHAIN_ID,
                amount: bridgedAmounts[i],
                minTokenAmount: Utils.calculateMinBridgeAmount(address(containerAgent), bridgedAmounts[i]),
                token: bridgedTokens[i],
                payload: ""
            });
        }

        return (messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function _toggleEmergencyResolutionMode(bool isEmergency) internal {
        uint256 value = uint256(vm.load(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT));

        if (isEmergency) {
            value |= (uint256(1) << IS_RESOLVING_EMERGENCY_OFFSET);
        } else {
            value &= ~(uint256(1) << IS_RESOLVING_EMERGENCY_OFFSET);
        }

        vm.store(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT, bytes32(value));
    }

    function _toggleReshufflingMode(bool isReshuffling) internal {
        uint256 value = uint256(vm.load(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT));

        if (isReshuffling) {
            value |= uint256(1);
        } else {
            value &= ~uint256(1);
        }

        vm.store(address(containerAgent), IS_RESOLVING_EMERGENCY_AND_RESHUFFLING_MODE_SLOT, bytes32(value));
    }
}
