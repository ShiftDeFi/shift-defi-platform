// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";

contract VaultWithdrawTest is VaultBaseTest {
    function test_Withdraw_SingleUserPartial() public {
        _giveUserShares(users.alice, DEFAULT_SHARES_AMOUNT);

        uint256 withdrawBatchId = vault.withdrawBatchId();
        uint256 expectedSharesToWithdraw = (DEFAULT_SHARES_AMOUNT * DEFAULT_SHARES_PERCENT) / MAX_BPS;

        uint256 aliceBalanceBefore = IERC20(address(vault)).balanceOf(users.alice);
        uint256 vaultBalanceBefore = IERC20(address(vault)).balanceOf(address(vault));
        uint256 bufferedSharesBefore = vault.bufferedSharesToWithdraw();
        uint256 pendingWithdrawalsBefore = vault.pendingBatchWithdrawals(withdrawBatchId, users.alice);

        vm.prank(users.alice);
        vault.withdraw(DEFAULT_SHARES_PERCENT);

        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            aliceBalanceBefore - expectedSharesToWithdraw,
            "test_Withdraw_SingleUserPartial: alice balance mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            vaultBalanceBefore + expectedSharesToWithdraw,
            "test_Withdraw_SingleUserPartial: vault balance mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            bufferedSharesBefore + expectedSharesToWithdraw,
            "test_Withdraw_SingleUserPartial: buffered shares mismatch"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            pendingWithdrawalsBefore + expectedSharesToWithdraw,
            "test_Withdraw_SingleUserPartial: pending batch withdrawals mismatch"
        );
    }

    function test_Withdraw_SingleUserFull() public {
        _giveUserShares(users.alice, DEFAULT_SHARES_AMOUNT);

        uint256 withdrawBatchId = vault.withdrawBatchId();

        vm.prank(users.alice);
        vault.withdraw(MAX_BPS);

        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            0,
            "test_Withdraw_SingleUserFull: alice balance should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            DEFAULT_SHARES_AMOUNT,
            "test_Withdraw_SingleUserFull: vault balance mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            DEFAULT_SHARES_AMOUNT,
            "test_Withdraw_SingleUserFull: buffered shares mismatch"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            DEFAULT_SHARES_AMOUNT,
            "test_Withdraw_SingleUserFull: pending batch withdrawals mismatch"
        );
    }

    function test_Withdraw_SingleUserSmallPercentage() public {
        _giveUserShares(users.alice, DEFAULT_SHARES_AMOUNT);

        uint256 withdrawBatchId = vault.withdrawBatchId();
        uint256 sharesPercent = 1; // 0.01%
        uint256 expectedSharesToWithdraw = _calculateExpectedSharesToWithdraw(DEFAULT_SHARES_AMOUNT, sharesPercent);
        vm.assertGt(
            expectedSharesToWithdraw,
            0,
            "test_Withdraw_SingleUserSmallPercentage: expected shares should be greater than zero"
        );

        vm.prank(users.alice);
        vault.withdraw(sharesPercent);

        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            DEFAULT_SHARES_AMOUNT - expectedSharesToWithdraw,
            "test_Withdraw_SingleUserSmallPercentage: alice balance mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            expectedSharesToWithdraw,
            "test_Withdraw_SingleUserSmallPercentage: buffered shares mismatch"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            expectedSharesToWithdraw,
            "test_Withdraw_SingleUserSmallPercentage: pending batch withdrawals mismatch"
        );
    }

    function test_Withdraw_MultipleUsers() public {
        uint256 sharesAmountAlice = vm.randomUint(1e18, 1000e18);
        uint256 sharesAmountBob = 2 * sharesAmountAlice;
        _giveUserShares(users.alice, sharesAmountAlice);
        _giveUserShares(users.bob, sharesAmountBob);

        uint256 withdrawBatchId = vault.withdrawBatchId();
        uint256 sharesPercent = 3000; // 30%

        uint256 expectedSharesAlice = _calculateExpectedSharesToWithdraw(sharesAmountAlice, sharesPercent);
        uint256 expectedSharesBob = _calculateExpectedSharesToWithdraw(sharesAmountBob, sharesPercent);

        vm.prank(users.alice);
        vault.withdraw(sharesPercent);

        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            expectedSharesAlice,
            "test_Withdraw_MultipleUsers: alice pending mismatch"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.bob),
            0,
            "test_Withdraw_MultipleUsers: bob pending should be zero"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            expectedSharesAlice,
            "test_Withdraw_MultipleUsers: buffered shares mismatch after alice"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            sharesAmountAlice - expectedSharesAlice,
            "test_Withdraw_MultipleUsers: alice balance mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            expectedSharesAlice,
            "test_Withdraw_MultipleUsers: vault balance mismatch after alice"
        );

        vm.prank(users.bob);
        vault.withdraw(sharesPercent);

        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            expectedSharesAlice,
            "test_Withdraw_MultipleUsers: alice pending after bob mismatch"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.bob),
            expectedSharesBob,
            "test_Withdraw_MultipleUsers: bob pending mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            expectedSharesAlice + expectedSharesBob,
            "test_Withdraw_MultipleUsers: buffered shares mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.bob),
            sharesAmountBob - expectedSharesBob,
            "test_Withdraw_MultipleUsers: bob balance mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            expectedSharesBob + expectedSharesAlice,
            "test_Withdraw_MultipleUsers: vault balance mismatch"
        );
    }

    function test_Withdraw_MultipleWithdrawalsSameUser() public {
        uint256 sharesAmount = 1000 * 1e18;
        _giveUserShares(users.alice, sharesAmount);

        uint256 withdrawBatchId = vault.withdrawBatchId();
        uint256 sharesPercent1 = 3000;
        uint256 sharesPercent2 = 2000;

        uint256 expectedShares1 = _calculateExpectedSharesToWithdraw(sharesAmount, sharesPercent1);

        vm.prank(users.alice);
        vault.withdraw(sharesPercent1);

        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            expectedShares1,
            "test_Withdraw_MultipleWithdrawalsSameUser: pending after first mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            expectedShares1,
            "test_Withdraw_MultipleWithdrawalsSameUser: buffered after first mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            sharesAmount - expectedShares1,
            "test_Withdraw_MultipleWithdrawalsSameUser: alice balance after first mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            expectedShares1,
            "test_Withdraw_MultipleWithdrawalsSameUser: vault balance after first mismatch"
        );

        uint256 remainingBalance = sharesAmount - expectedShares1;
        uint256 expectedShares2 = _calculateExpectedSharesToWithdraw(remainingBalance, sharesPercent2);

        vm.prank(users.alice);
        vault.withdraw(sharesPercent2);

        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            expectedShares1 + expectedShares2,
            "test_Withdraw_MultipleWithdrawalsSameUser: pending after second mismatch"
        );
        vm.assertEq(
            vault.bufferedSharesToWithdraw(),
            expectedShares1 + expectedShares2,
            "test_Withdraw_MultipleWithdrawalsSameUser: buffered after second mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            remainingBalance - expectedShares2,
            "test_Withdraw_MultipleWithdrawalsSameUser: alice balance after second mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            expectedShares2 + expectedShares1,
            "test_Withdraw_MultipleWithdrawalsSameUser: vault balance after second mismatch"
        );
    }

    function test_ReverIf_Withdraw_SharesPercentOutOfBounds() public {
        _giveUserShares(users.alice, DEFAULT_SHARES_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.withdraw(0);

        vm.prank(users.alice);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.withdraw(MAX_BPS + 1);
    }

    function test_RevertIf_Withdraw_NothingToWithdraw() public {
        vm.prank(users.alice);
        vm.expectRevert(IVault.NothingToWithdraw.selector);
        vault.withdraw(MAX_BPS);
    }

    function test_RevertIf_Withdraw_NothingToWithdrawAfterCalculation() public {
        uint256 sharesAmount = 1;
        _giveUserShares(users.alice, sharesAmount);

        vm.prank(users.alice);
        vm.expectRevert(IVault.NothingToWithdraw.selector);
        vault.withdraw(1);
    }

    function test_RevertIf_Withdraw_VaultInReshufflingMode() public {
        _giveUserShares(users.alice, DEFAULT_SHARES_AMOUNT);

        address mockGateway = address(0x1234);
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(mockGateway);

        vm.prank(roles.emergencyManager);
        vault.setReshufflingMode(true);

        vm.prank(users.alice);
        vm.expectRevert(IVault.VaultIsInReshufflingMode.selector);
        vault.withdraw(DEFAULT_SHARES_PERCENT);
    }
}
