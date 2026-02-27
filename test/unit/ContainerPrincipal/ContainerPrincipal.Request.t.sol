// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {Codec} from "contracts/libraries/Codec.sol";

import {ContainerPrincipalBaseTest} from "test/unit/ContainerPrincipal/ContainerPrincipalBase.t.sol";

contract ContainerPrincipalRequestTest is ContainerPrincipalBaseTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
    }

    function test_RegisterDepositRequest() public {
        uint256 depositAmount = vault.minDepositAmount();
        _deposit(users.alice, depositAmount);

        vm.prank(address(vault));
        containerPrincipal.registerDepositRequest(depositAmount);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestRegistered)
        );
        assertEq(
            notion.balanceOf(address(containerPrincipal)),
            depositAmount,
            "test_RegisterDepositRequest: balance mismatch"
        );
    }

    function test_RevertIf_StatusNotIdleAndRegisterDepositRequest() public {
        uint256 depositAmount = vault.minDepositAmount();
        _deposit(users.alice, depositAmount);

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestRegistered);

        vm.prank(address(vault));
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerPrincipal.registerDepositRequest(depositAmount);
    }

    function test_RegisterWithdrawRequest() public {
        uint256 withdrawShareAmount = vault.minWithdrawBatchRatio();
        vm.prank(address(vault));
        containerPrincipal.registerWithdrawRequest(withdrawShareAmount);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestRegistered),
            "test_RegisterWithdrawRequest: status mismatch"
        );
        assertEq(
            containerPrincipal.registeredWithdrawShareAmount(),
            withdrawShareAmount,
            "test_RegisterWithdrawRequest: registeredWithdrawShareAmount mismatch"
        );
    }

    function test_RevertIf_StatusNotIdleAndRegisterWithdrawRequest() public {
        uint256 withdrawShareAmount = vault.minWithdrawBatchRatio();

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestRegistered);

        vm.prank(address(vault));
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerPrincipal.registerWithdrawRequest(withdrawShareAmount);
    }

    function test_RevertIf_RegisterWithdrawRequestWithZeroShareAmount() public {
        vm.prank(address(vault));
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerPrincipal.registerWithdrawRequest(0);
    }

    function test_SendDepositRequest() public {
        uint256 depositAmount = vault.minDepositBatchSize();
        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareDepositRequestData(depositAmount);

        vm.prank(roles.operator);
        containerPrincipal.sendDepositRequest(messageInstruction, bridgeAdapters, bridgeInstructions);

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent),
            "test_SendDepositRequest: status mismatch"
        );
        assertEq(
            notion.balanceOf(address(containerPrincipal)),
            0,
            "test_SendDepositRequest: container balance mismatch"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            depositAmount,
            "test_SendDepositRequest: bridge adapter balance mismatch"
        );
    }

    function test_RevertIf_StatusNotDepositRequestRegisteredAndSendDepositRequest() public {
        uint256 depositAmount = vault.minDepositBatchSize();

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareDepositRequestData(depositAmount);

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);

        vm.prank(roles.operator);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerPrincipal.sendDepositRequest(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_SendDepositRequestWithMessageAdapterIsZeroAddress() public {
        uint256 depositAmount = vault.minDepositBatchSize();

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareDepositRequestData(depositAmount);

        messageInstruction.adapter = address(0);

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestRegistered);

        vm.prank(roles.operator);
        vm.expectRevert(Errors.ZeroAddress.selector);
        containerPrincipal.sendDepositRequest(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_SendDepositRequestWithOtherTokensPresent() public {
        uint256 depositAmount = vault.minDepositBatchSize();
        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareDepositRequestData(depositAmount);

        _whitelistToken(address(containerPrincipal), address(dai));
        uint256 daiDustThreshold = vault.minDepositAmount();
        vm.prank(roles.tokenManager);
        containerPrincipal.setWhitelistedTokenDustThreshold(address(dai), daiDustThreshold);

        dai.mint(address(containerPrincipal), daiDustThreshold + 1);
        vm.prank(roles.operator);
        vm.expectRevert(IContainer.WhitelistedTokensOnBalance.selector);
        containerPrincipal.sendDepositRequest(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_SendWithdrawRequest() public {
        uint256 nonce = 1;
        uint256 withdrawShareAmount = vault.minWithdrawBatchRatio();
        vm.prank(address(vault));
        containerPrincipal.registerWithdrawRequest(withdrawShareAmount);

        vm.prank(roles.operator);
        containerPrincipal.sendWithdrawRequest(
            ICrossChainContainer.MessageInstruction({adapter: address(messageAdapter), parameters: ""})
        );

        bytes32 path = messageRouter.calculatePath(
            address(containerPrincipal),
            containerPrincipal.peerContainer(),
            block.chainid
        );

        bytes memory message = Codec.encode(Codec.WithdrawalRequest({share: withdrawShareAmount}));

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent)
        );

        assertTrue(
            messageRouter.isMessageCached(containerPrincipal.remoteChainId(), nonce, path, message),
            "test_SendWithdrawRequest: message not cached"
        );
    }

    function test_RevertIf_SendWithdrawRequestWithZeroShareAmount() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestRegistered);

        vm.prank(roles.operator);
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerPrincipal.sendWithdrawRequest(
            ICrossChainContainer.MessageInstruction({adapter: address(messageAdapter), parameters: ""})
        );
    }
}
