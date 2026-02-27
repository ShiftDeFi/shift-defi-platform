// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {ContainerPrincipalBaseTest} from "test/unit/ContainerPrincipal/ContainerPrincipalBase.t.sol";

contract ContainerPrincipalClaimTest is ContainerPrincipalBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function _prepareToClaimSingleToken(address token, uint256 amount) internal {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        bytes memory message = _craftWithdrawalResponseMessageSingleToken(token, amount);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        MockERC20(token).mint(address(bridgeAdapter), amount);
        bridgeAdapter.finalizeBridge(address(containerPrincipal), token, amount);
    }

    function _prepareToClaimMultipleTokens(address[] memory tokens, uint256[] memory amounts) internal {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        bytes memory message = _craftWithdrawalResponseMessageMultipleTokens(tokens, amounts);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        for (uint256 i = 0; i < tokens.length; i++) {
            MockERC20(tokens[i]).mint(address(bridgeAdapter), amounts[i]);
            bridgeAdapter.finalizeBridge(address(containerPrincipal), tokens[i], amounts[i]);
        }
    }

    function test_ClaimSingleToken() public {
        uint256 batchSize = vault.minDepositBatchSize();
        _prepareToClaimSingleToken(address(notion), batchSize);

        vm.prank(roles.operator);
        containerPrincipal.claim(address(bridgeAdapter), address(notion));

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed),
            "test_ClaimSingleToken: status mismatch"
        );
        assertEq(containerPrincipal.claimCounter(), 0, "test_ClaimSingleToken: claim counter mismatch");

        assertEq(
            _getAddressUintMappingValue(address(containerPrincipal), EXPECTED_TOKEN_AMOUNT_SLOT, address(notion)),
            0,
            "test_ClaimSingleToken: expected token amount mismatch"
        );
    }

    function test_ClaimOneTokenOutOfMany() public {
        _whitelistToken(address(containerPrincipal), address(dai));

        uint256 batchSize = vault.maxDepositBatchSize();
        uint256 daiAmount = batchSize / 2;
        uint256 notionAmount = batchSize - daiAmount;

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = daiAmount;
        amounts[1] = notionAmount;

        _prepareToClaimMultipleTokens(tokens, amounts);

        vm.prank(roles.operator);
        containerPrincipal.claim(address(bridgeAdapter), address(dai));

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalResponseReceived),
            "test_ClaimOneTokenOutOfMany: status mismatch"
        );
        assertEq(containerPrincipal.claimCounter(), 1, "test_ClaimOneTokenOutOfMany: claim counter mismatch");
    }

    function test_RevertIf_ClaimSingleTokenWithIncorrectStatus() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerPrincipal.claim(address(bridgeAdapter), address(notion));
    }

    function test_ClaimMultipleTokens() public {
        _whitelistToken(address(containerPrincipal), address(dai));

        uint256 batchSize = vault.maxDepositBatchSize();
        uint256 daiAmount = batchSize / 2;
        uint256 notionAmount = batchSize - daiAmount;

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = daiAmount;
        amounts[1] = notionAmount;

        address[] memory bridgeAdapters = new address[](2);
        bridgeAdapters[0] = address(bridgeAdapter);
        bridgeAdapters[1] = address(bridgeAdapter);

        _prepareToClaimMultipleTokens(tokens, amounts);

        vm.prank(roles.operator);
        containerPrincipal.claimMultiple(bridgeAdapters, tokens);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed),
            "test_ClaimMultipleTokens: status mismatch"
        );
        assertEq(containerPrincipal.claimCounter(), 0, "test_ClaimMultipleTokens: claim counter mismatch");
    }

    function test_RevertIf_ClaimMultipleTokensWithDifferentLengths() public {
        uint256 batchSize = vault.maxDepositBatchSize();
        uint256 daiAmount = batchSize / 2;
        uint256 notionAmount = batchSize - daiAmount;

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = daiAmount;
        amounts[1] = notionAmount;

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        _whitelistToken(address(containerPrincipal), address(dai));
        _prepareToClaimMultipleTokens(tokens, amounts);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.operator);
        containerPrincipal.claimMultiple(bridgeAdapters, tokens);
    }

    function test_RevertIf_ClaimMultipleTokensWithIncorrectStatus() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);

        address[] memory bridgeAdapters = new address[](2);
        bridgeAdapters[0] = address(bridgeAdapter);
        bridgeAdapters[1] = address(bridgeAdapter);

        address[] memory tokens = new address[](2);
        tokens[0] = address(dai);
        tokens[1] = address(notion);

        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerPrincipal.claimMultiple(bridgeAdapters, tokens);
    }
}
