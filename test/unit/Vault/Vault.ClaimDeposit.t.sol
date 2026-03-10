// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";

contract VaultClaimDepositTest is VaultBaseTest {
    uint256 internal depositBatchId;
    uint256 internal depositAmount;

    function setUp() public override {
        super.setUp();
        depositBatchId = vault.depositBatchId();
        depositAmount = vm.randomUint(vault.minDepositAmount(), vault.maxDepositAmount());

        _deposit(users.alice, depositAmount);
    }

    function test_ClaimDeposit_SingleUserWithoutRemainder() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersWithoutRemainder(depositAmount);
        _resolveDepositBatch();

        (uint256 sharesClaimed, uint256 notionClaimed) = vault.claimDeposit(depositBatchId, users.alice);

        vm.assertGt(sharesClaimed, 0, "test_ClaimDeposit_SingleUserWithoutRemainder: sharesClaimed should be > 0");
        vm.assertEq(notionClaimed, 0, "test_ClaimDeposit_SingleUserWithoutRemainder: notionClaimed should be 0");
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.alice),
            0,
            "test_ClaimDeposit_SingleUserWithoutRemainder: alice pending should be zero"
        );
        vm.assertEq(
            vault.totalUnclaimedNotionRemainder(),
            0,
            "test_ClaimDeposit_SingleUserWithoutRemainder: total unclaimed remainder should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            sharesClaimed,
            "test_ClaimDeposit_SingleUserWithoutRemainder: alice shares should match claimed"
        );
    }

    function test_ClaimDeposit_TwoUsersWithoutRemainder() public {
        _deposit(users.bob, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersWithoutRemainder(2 * depositAmount);
        _resolveDepositBatch();

        (uint256 aliceSharesClaimed, uint256 aliceNotionClaimed) = vault.claimDeposit(depositBatchId, users.alice);

        vm.assertGt(aliceSharesClaimed, 0, "test_ClaimDeposit_TwoUsersWithoutRemainder: alice sharesClaimed > 0");
        vm.assertEq(
            aliceNotionClaimed,
            0,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: alice notionClaimed should be 0"
        );
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.alice),
            0,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: alice pending should be zero"
        );
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.bob),
            depositAmount,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: bob pending mismatch"
        );
        vm.assertEq(
            vault.totalUnclaimedNotionRemainder(),
            0,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: total unclaimed remainder should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            aliceSharesClaimed,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: alice shares should match claimed"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.bob),
            0,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: bob shares should be zero before claim"
        );

        (uint256 bobSharesClaimed, uint256 bobNotionClaimed) = vault.claimDeposit(depositBatchId, users.bob);

        vm.assertGt(bobSharesClaimed, 0, "test_ClaimDeposit_TwoUsersWithoutRemainder: bob sharesClaimed > 0");
        vm.assertEq(bobNotionClaimed, 0, "test_ClaimDeposit_TwoUsersWithoutRemainder: bob notionClaimed should be 0");
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.bob),
            0,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: bob pending should be zero after claim"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.bob),
            bobSharesClaimed,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: bob shares should match claimed"
        );
        vm.assertEq(
            bobSharesClaimed,
            aliceSharesClaimed,
            "test_ClaimDeposit_TwoUsersWithoutRemainder: alice and bob shares should be equal"
        );
    }

    function test_ClaimDeposit_SingleUserWithRemainder() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        uint256 totalRemainder;
        (, totalRemainder) = _reportDepositBatchAllContainersWithRemainder(depositAmount);
        _resolveDepositBatch();

        (uint256 sharesClaimed, uint256 notionClaimed) = vault.claimDeposit(depositBatchId, users.alice);

        vm.assertGt(sharesClaimed, 0, "test_ClaimDeposit_SingleUserWithRemainder: sharesClaimed > 0");
        vm.assertEq(
            notionClaimed,
            totalRemainder,
            "test_ClaimDeposit_SingleUserWithRemainder: notionClaimed should match remainder"
        );
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.alice),
            0,
            "test_ClaimDeposit_SingleUserWithRemainder: alice pending should be zero"
        );
        vm.assertEq(
            vault.totalUnclaimedNotionRemainder(),
            0,
            "test_ClaimDeposit_SingleUserWithRemainder: total unclaimed remainder should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            sharesClaimed,
            "test_ClaimDeposit_SingleUserWithRemainder: alice shares should match claimed"
        );
        vm.assertEq(
            IERC20(address(notion)).balanceOf(users.alice),
            notionClaimed,
            "test_ClaimDeposit_SingleUserWithRemainder: alice notion remainder mismatch"
        );
        vm.assertGt(
            totalRemainder,
            0,
            "test_ClaimDeposit_SingleUserWithRemainder: total remainder should be greater than zero"
        );
    }

    function test_ClaimDeposit_SingleUserWithoutNavChange() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersOnlyNotion(depositAmount);
        _resolveDepositBatch();

        (uint256 sharesClaimed, uint256 notionClaimed) = vault.claimDeposit(depositBatchId, users.alice);

        vm.assertEq(sharesClaimed, 0, "test_ClaimDeposit_SingleUserWithoutNavChange: sharesClaimed should be 0");
        vm.assertGt(notionClaimed, 0, "test_ClaimDeposit_SingleUserWithoutNavChange: notionClaimed > 0");
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.alice),
            0,
            "test_ClaimDeposit_SingleUserWithoutNavChange: alice pending should be zero"
        );
        vm.assertEq(
            vault.totalUnclaimedNotionRemainder(),
            0,
            "test_ClaimDeposit_SingleUserWithoutNavChange: total unclaimed remainder should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            0,
            "test_ClaimDeposit_SingleUserWithoutNavChange: alice shares should be zero"
        );
        vm.assertGt(
            IERC20(address(notion)).balanceOf(users.alice),
            depositAmount - 100,
            "test_ClaimDeposit_SingleUserWithoutNavChange: alice notion balance mismatch"
        );
    }

    function test_ClaimDeposit_ReturnsZeroWhenNothingToClaim() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersEmpty();
        _resolveDepositBatch();

        (uint256 sharesClaimed, uint256 notionClaimed) = vault.claimDeposit(depositBatchId, users.bob);
        vm.assertEq(sharesClaimed, 0, "test_ClaimDeposit_ReturnsZeroWhenNothingToClaim: sharesClaimed should be 0");
        vm.assertEq(notionClaimed, 0, "test_ClaimDeposit_ReturnsZeroWhenNothingToClaim: notionClaimed should be 0");
    }

    function test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersEmpty();
        _resolveDepositBatch();

        uint256 aliceSharesBefore = IERC20(address(vault)).balanceOf(users.alice);
        uint256 aliceNotionBefore = notion.balanceOf(users.alice);

        (uint256 sharesClaimed, uint256 notionClaimed) = vault.claimDeposit(depositBatchId, users.alice);

        vm.assertEq(
            sharesClaimed,
            0,
            "test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder: sharesClaimed should be 0"
        );
        vm.assertEq(
            notionClaimed,
            0,
            "test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder: notionClaimed should be 0"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(users.alice),
            aliceSharesBefore,
            "test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder: alice shares should be unchanged"
        );
        vm.assertEq(
            notion.balanceOf(users.alice),
            aliceNotionBefore,
            "test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder: alice notion should be unchanged"
        );
        vm.assertEq(
            vault.pendingBatchDeposits(depositBatchId, users.alice),
            0,
            "test_ClaimDeposit_BatchMintsZeroSharesAndNoRemainder: pending should be cleared after claim"
        );
    }

    function test_RevertIf_ClaimDeposit_IncorrectBatchId() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersWithRemainder(depositAmount);
        _resolveDepositBatch();

        vm.expectRevert(IVault.IncorrectBatchId.selector);
        vault.claimDeposit(depositBatchId + 1, users.alice);
    }

    function test_RevertIf_ClaimDeposit_ClaimOnBehalfOfZeroAddress() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersEmpty();
        _resolveDepositBatch();

        vm.expectRevert(Errors.ZeroAddress.selector);
        vault.claimDeposit(depositBatchId, address(0));
    }

    function test_RevertIf_ClaimDeposit_NotEnoughNotion() public {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersWithRemainder(depositAmount);
        _resolveDepositBatch();

        uint256 vaultBalance = IERC20(address(notion)).balanceOf(address(vault));

        vm.prank(address(vault));
        IERC20(address(notion)).transfer(address(0x1), vaultBalance / 2);

        vm.expectRevert(IVault.NotEnoughNotion.selector);
        vault.claimDeposit(depositBatchId, users.alice);
    }
}
