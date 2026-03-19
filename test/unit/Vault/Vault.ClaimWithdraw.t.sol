// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";

contract VaultClaimWithdrawTest is VaultBaseTest {
    function test_ClaimWithdraw_SingleUser() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        uint256 withdrawnShares = vault.pendingBatchWithdrawals(withdrawBatchId, users.alice);
        uint256 expectedNotion = _calculateExpectedNotion(withdrawBatchId, users.alice);

        uint256 aliceNotionBefore = notion.balanceOf(users.alice);
        uint256 vaultSharesBefore = IERC20(address(vault)).balanceOf(address(vault));
        uint256 totalSupplyBefore = IERC20(address(vault)).totalSupply();
        uint256 totalUnclaimedBefore = vault.totalUnclaimedNotionForWithdraw();

        uint256 notionClaimed = vault.claimWithdraw(withdrawBatchId, users.alice);

        vm.assertEq(
            notionClaimed,
            expectedNotion,
            "test_ClaimWithdraw_SingleUser: notionClaimed should match expected"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            0,
            "test_ClaimWithdraw_SingleUser: alice pending should be zero"
        );
        vm.assertEq(
            notion.balanceOf(users.alice),
            aliceNotionBefore + expectedNotion,
            "test_ClaimWithdraw_SingleUser: alice notion balance mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            vaultSharesBefore - withdrawnShares,
            "test_ClaimWithdraw_SingleUser: vault shares mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).totalSupply(),
            totalSupplyBefore - withdrawnShares,
            "test_ClaimWithdraw_SingleUser: total supply mismatch"
        );
        vm.assertEq(
            vault.totalUnclaimedNotionForWithdraw(),
            totalUnclaimedBefore - expectedNotion,
            "test_ClaimWithdraw_SingleUser: total unclaimed notion mismatch"
        );
    }

    function test_ClaimWithdraw_TwoUsers() public {
        uint256 aliceShares = vm.randomUint(1e18, 100e18);
        uint256 bobShares = vm.randomUint(1e18, 100e18);
        uint256 aliceWithdrawPct = vm.randomUint(1, MAX_BPS);
        uint256 bobWithdrawPct = vm.randomUint(1, MAX_BPS);

        _giveUserShares(users.alice, aliceShares);
        _giveUserShares(users.bob, bobShares);

        vm.prank(users.alice);
        vault.withdraw(aliceWithdrawPct);
        vm.prank(users.bob);
        vault.withdraw(bobWithdrawPct);

        uint256 withdrawBatchId = _processResolvedWithdrawBatch();

        uint256 withdrawnSharesAlice = vault.pendingBatchWithdrawals(withdrawBatchId, users.alice);
        uint256 withdrawnSharesBob = vault.pendingBatchWithdrawals(withdrawBatchId, users.bob);

        uint256 aliceNotionBefore = notion.balanceOf(users.alice);
        uint256 expectedNotionAlice = _calculateExpectedNotion(withdrawBatchId, users.alice);

        vm.assertGt(
            withdrawnSharesAlice,
            0,
            "test_ClaimWithdraw_TwoUsers: alice withdrawn shares should be greater than zero"
        );
        vm.assertGt(
            withdrawnSharesBob,
            0,
            "test_ClaimWithdraw_TwoUsers: bob withdrawn shares should be greater than zero"
        );

        uint256 aliceNotionClaimed = vault.claimWithdraw(withdrawBatchId, users.alice);

        vm.assertEq(
            aliceNotionClaimed,
            expectedNotionAlice,
            "test_ClaimWithdraw_TwoUsers: alice notionClaimed should match expected"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.alice),
            0,
            "test_ClaimWithdraw_TwoUsers: alice pending should be zero"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.bob),
            withdrawnSharesBob,
            "test_ClaimWithdraw_TwoUsers: bob pending mismatch"
        );
        vm.assertEq(
            notion.balanceOf(users.alice),
            expectedNotionAlice + aliceNotionBefore,
            "test_ClaimWithdraw_TwoUsers: alice notion balance mismatch"
        );
        vm.assertEq(
            notion.balanceOf(users.bob),
            0,
            "test_ClaimWithdraw_TwoUsers: bob notion should be zero before claim"
        );

        uint256 expectedNotionBob = _calculateExpectedNotion(withdrawBatchId, users.bob);
        uint256 bobNotionBefore = notion.balanceOf(users.bob);

        uint256 bobNotionClaimed = vault.claimWithdraw(withdrawBatchId, users.bob);

        vm.assertEq(
            bobNotionClaimed,
            expectedNotionBob,
            "test_ClaimWithdraw_TwoUsers: bob notionClaimed should match expected"
        );
        vm.assertEq(
            vault.pendingBatchWithdrawals(withdrawBatchId, users.bob),
            0,
            "test_ClaimWithdraw_TwoUsers: bob pending should be zero after claim"
        );
        vm.assertEq(
            notion.balanceOf(users.bob),
            bobNotionBefore + expectedNotionBob,
            "test_ClaimWithdraw_TwoUsers: bob notion balance mismatch"
        );
    }

    function test_ClaimWithdraw_ProportionalNotion() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        uint256 expectedNotion = _calculateExpectedNotion(withdrawBatchId, users.alice);

        uint256 aliceNotionBefore = notion.balanceOf(users.alice);
        uint256 notionClaimed = vault.claimWithdraw(withdrawBatchId, users.alice);

        vm.assertEq(
            notionClaimed,
            expectedNotion,
            "test_ClaimWithdraw_ProportionalNotion: notionClaimed should match expected"
        );
        vm.assertEq(
            notion.balanceOf(users.alice),
            aliceNotionBefore + expectedNotion,
            "test_ClaimWithdraw_ProportionalNotion: alice notion balance mismatch"
        );
    }

    function test_RevertIf_ClaimWithdraw_IncorrectBatchId() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        vm.expectRevert(IVault.IncorrectBatchId.selector);
        vault.claimWithdraw(withdrawBatchId + 1, users.alice);
    }

    function test_RevertIf_ClaimWithdraw_ClaimOnBehalfOfZeroAddress() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vault.claimWithdraw(withdrawBatchId, address(0));
    }

    function test_ClaimWithdraw_ReturnsZeroWhenNothingToClaim() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        vault.claimWithdraw(withdrawBatchId, users.alice);

        uint256 notionClaimed = vault.claimWithdraw(withdrawBatchId, users.alice);
        vm.assertEq(notionClaimed, 0, "test_ClaimWithdraw_ReturnsZeroWhenNothingToClaim: second claim should return 0");
    }

    function test_ClaimWithdraw_ReturnsZeroWhenNothingToClaimForOtherUser() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        uint256 notionClaimed = vault.claimWithdraw(withdrawBatchId, users.bob);
        vm.assertEq(
            notionClaimed,
            0,
            "test_ClaimWithdraw_ReturnsZeroWhenNothingToClaimForOtherUser: bob claim should return 0"
        );
    }

    function test_RevertIf_ClaimWithdraw_NotEnoughNotion() public {
        uint256 withdrawBatchId = _processSingleUserResolvedWithdrawBatch(users.alice);

        deal(address(notion), address(vault), 0);

        vm.expectRevert(IVault.NotEnoughNotion.selector);
        vault.claimWithdraw(withdrawBatchId, users.alice);
    }
}
