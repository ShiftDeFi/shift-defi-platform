// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {MockBridgeAdapter} from "test/mocks/MockBridgeAdapter.sol";
import {ContainerAgentBaseTest} from "test/unit/ContainerAgent/ContainerAgentBase.t.sol";

contract ContainerAgentClaimTest is ContainerAgentBaseTest {
    uint256 internal tokenNumber = 2;

    function setUp() public override {
        super.setUp();

        vm.prank(roles.tokenManager);
        containerAgent.whitelistToken(address(dai));
        address[] memory tokens = new address[](tokenNumber);
        tokens[0] = address(dai);
        tokens[1] = address(notion);
        uint256[] memory amounts = new uint256[](tokenNumber);
        amounts[0] = DEPOSIT_AMOUNT;
        amounts[1] = DEPOSIT_AMOUNT;

        bytes memory rawMessage = _craftDepositRequestMessage(tokens, amounts);
        vm.prank(address(messageRouter));
        containerAgent.receiveMessage(rawMessage);

        dai.mint(address(bridgeAdapter), DEPOSIT_AMOUNT);
        notion.mint(address(bridgeAdapter), DEPOSIT_AMOUNT);

        MockBridgeAdapter(payable(address(bridgeAdapter))).finalizeBridge(
            address(containerAgent),
            address(dai),
            DEPOSIT_AMOUNT
        );
        MockBridgeAdapter(payable(address(bridgeAdapter))).finalizeBridge(
            address(containerAgent),
            address(notion),
            DEPOSIT_AMOUNT
        );
    }

    function test_Claim() public {
        vm.prank(roles.operator);
        containerAgent.claim(address(bridgeAdapter), address(dai));

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.DepositRequestReceived),
            "test_Claim: status not DepositRequestReceived"
        );
        assertEq(containerAgent.claimCounter(), tokenNumber - 1, "test_Claim: claim counter not decreased");
        assertEq(dai.balanceOf(address(containerAgent)), DEPOSIT_AMOUNT, "test_Claim: dai balance not updated");

        vm.prank(roles.operator);
        containerAgent.claim(address(bridgeAdapter), address(notion));

        assertEq(
            uint256(containerAgent.status()),
            uint256(IContainerAgent.ContainerAgentStatus.BridgeClaimed),
            "test_Claim: status not BridgeClaimed"
        );
        assertEq(containerAgent.claimCounter(), 0, "test_Claim: claim counter not 0");
        assertEq(notion.balanceOf(address(containerAgent)), DEPOSIT_AMOUNT, "test_Claim: notion balance not updated");
    }

    function test_RevertIf_Claim_IncorrectContainerStatus() public {
        _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus.WithdrawalRequestReceived);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerAgent.claim(address(bridgeAdapter), address(dai));
    }

    function test_RevertIf_Claim_InReshufflingMode() public {
        _toggleReshufflingMode(true);
        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.operator);
        containerAgent.claim(address(bridgeAdapter), address(dai));
    }

    function test_RevertIf_Claim_InEmergencyResolutionMode() public {
        _toggleEmergencyResolutionMode(true);
        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        vm.prank(roles.operator);
        containerAgent.claim(address(bridgeAdapter), address(dai));
    }

    function test_ClaimInReshufflingMode() public {
        _toggleReshufflingMode(true);

        MockBridgeAdapter newBridgeAdapter = _deployBridgeAdapter();
        vm.prank(roles.bridgeAdapterManager);
        containerAgent.setBridgeAdapter(address(newBridgeAdapter), true);

        dai.mint(address(newBridgeAdapter), DEPOSIT_AMOUNT);
        newBridgeAdapter.finalizeBridge(address(containerAgent), address(dai), DEPOSIT_AMOUNT);

        vm.prank(roles.reshufflingExecutor);
        containerAgent.claimInReshufflingMode(address(newBridgeAdapter), address(dai));

        assertEq(dai.balanceOf(address(newBridgeAdapter)), 0, "test_ClaimInReshufflingMode: dai balance not zero");
        assertEq(
            dai.balanceOf(address(containerAgent)),
            DEPOSIT_AMOUNT,
            "test_ClaimInReshufflingMode: dai balance not updated"
        );
    }

    function test_RevertIf_ClaimInReshufflingMode_IncorrectBridgeAdapter() public {
        _toggleReshufflingMode(true);

        address newBridgeAdapter = address(_deployBridgeAdapter());

        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        vm.prank(roles.reshufflingExecutor);
        containerAgent.claimInReshufflingMode(newBridgeAdapter, address(dai));
    }

    function test_RevertIf_ClaimInReshufflingMode_NotWhitelistedToken() public {
        _toggleReshufflingMode(true);

        address notWhitelistedToken = address(0x123);

        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, notWhitelistedToken));
        vm.prank(roles.reshufflingExecutor);
        containerAgent.claimInReshufflingMode(address(bridgeAdapter), notWhitelistedToken);
    }
}
