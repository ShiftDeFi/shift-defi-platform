// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

contract VaultWithdrawBatchProcessingTest is VaultBaseTest {
    function setUp() public override {
        super.setUp();
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingFinished);
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));
    }

    function test_StartWithdrawBatchProcessing() public {
        uint256 previousWithdrawBatchId = vault.withdrawBatchId();
        uint256 withdrawSharesPercent = MAX_BPS / 2;

        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);
        uint256 totalShares = IERC20(address(vault)).totalSupply();
        uint256 expectedShares = (totalShares * withdrawSharesPercent) / MAX_BPS;

        vm.prank(users.alice);
        vault.withdraw(withdrawSharesPercent);

        vm.prank(roles.operator);
        vault.startWithdrawBatchProcessing();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.WithdrawBatchProcessingStarted));
        assertEq(vault.withdrawBatchId(), previousWithdrawBatchId + 1);
        assertEq(vault.withdrawBatchTotalShares(previousWithdrawBatchId), expectedShares);
        assertEq(vault.bufferedSharesToWithdraw(), 0);
        assertEq(vault.pendingBatchWithdrawals(previousWithdrawBatchId, users.alice), expectedShares);
    }

    function test_StartWithdrawBatchProcessing_TwoUsers() public {
        uint256 previousWithdrawBatchId = vault.withdrawBatchId();
        uint256 withdrawSharesPercent = MAX_BPS / 2;

        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);
        _giveUserShares(users.bob, WITHDRAW_SHARES_AMOUNT);

        uint256 totalShares = IERC20(address(vault)).totalSupply();
        uint256 expectedShares = (totalShares * withdrawSharesPercent) / MAX_BPS;

        vm.prank(users.alice);
        vault.withdraw(withdrawSharesPercent);
        vm.prank(users.bob);
        vault.withdraw(withdrawSharesPercent);

        vm.prank(roles.operator);
        vault.startWithdrawBatchProcessing();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.WithdrawBatchProcessingStarted));
        assertEq(vault.withdrawBatchId(), previousWithdrawBatchId + 1);
        assertEq(vault.withdrawBatchTotalShares(previousWithdrawBatchId), expectedShares);
        assertEq(vault.bufferedSharesToWithdraw(), 0);
        assertEq(vault.pendingBatchWithdrawals(previousWithdrawBatchId, users.alice), expectedShares / 2);
        assertEq(vault.pendingBatchWithdrawals(previousWithdrawBatchId, users.bob), expectedShares / 2);
    }

    function test_RevertIf_StartWithdrawBatchProcessing_IncorrectVaultStates() public {
        uint256 withdrawSharesPercent = MAX_BPS / 2;

        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);

        vm.prank(users.alice);
        vault.withdraw(withdrawSharesPercent);

        _setVaultStatus(IVault.VaultStatus.Idle);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.IncorrectVaultStatus.selector);
        vault.startWithdrawBatchProcessing();
    }

    function test_RevertIf_StartWithdrawBatchProcessing_NotOperator() public {
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, users.alice, OPERATOR_ROLE)
        );
        vault.startWithdrawBatchProcessing();
    }

    function test_RevertIf_StartWithdrawBatchProcessing_NotEnoughSharesWithdrawn() public {
        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);

        vm.prank(users.alice);
        vault.withdraw(MIN_WITHDRAW_BATCH_RATIO - 1);

        uint256 expectedBatchSharesPercent = (vault.bufferedSharesToWithdraw() * MAX_BPS) /
            IERC20(address(vault)).totalSupply();

        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IVault.NotEnoughSharesWithdrawn.selector, expectedBatchSharesPercent));
        vault.startWithdrawBatchProcessing();
    }

    function test_RevertIf_StartWithdrawBatchProcessing_InReshufflingMode() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingMode(true);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.VaultIsInReshufflingMode.selector);
        vault.startWithdrawBatchProcessing();
    }

    function test_SkipWithdrawBatch() public {
        uint256 previousWithdrawBatchId = vault.withdrawBatchId();
        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);

        vm.prank(users.alice);
        vault.withdraw(MIN_WITHDRAW_BATCH_RATIO - 1);

        uint256 bufferedSharesToWithdraw = vault.bufferedSharesToWithdraw();

        vm.prank(roles.operator);
        vault.skipWithdrawBatch();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.Idle));
        assertEq(vault.withdrawBatchId(), previousWithdrawBatchId);
        assertEq(vault.bufferedSharesToWithdraw(), bufferedSharesToWithdraw);
    }

    function test_RevertIf_SkipWithdrawBatch_BatchNotInIdleStatus() public {
        _setVaultStatus(IVault.VaultStatus.WithdrawBatchProcessingStarted);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.IncorrectVaultStatus.selector);
        vault.skipWithdrawBatch();
    }

    function test_RevertIf_SkipWithdrawBatch_WithEnoughShares() public {
        _giveUserShares(users.alice, WITHDRAW_SHARES_AMOUNT);

        vm.prank(users.alice);
        vault.withdraw(MIN_WITHDRAW_BATCH_RATIO + 1);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.CannotSkipBatch.selector);
        vault.skipWithdrawBatch();
    }
}
