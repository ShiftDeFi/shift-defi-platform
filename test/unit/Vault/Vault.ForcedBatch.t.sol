// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Vault} from "contracts/Vault.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";

contract VaultForcedBatchTest is VaultBaseTest {
    using Math for uint256;

    uint256 internal constant SHARES_WITHDRAW_PERCENT = 0.1e18; // 1%

    function setUp() public override {
        super.setUp();
        _giveUserShares(users.alice, FORCED_WITHDRAW_THRESHOLD.mulDiv(MAX_BPS, SHARES_WITHDRAW_PERCENT));
        vm.prank(roles.configurator);
        vault.setMinWithdrawBatchRatio(SHARES_WITHDRAW_PERCENT + 1);
    }

    function test_SetForcedDepositThreshold() public {
        uint256 newThreshold = 2_000 * NOTION_PRECISION;
        vm.prank(roles.configurator);
        vault.setForcedDepositThreshold(newThreshold);
        assertEq(vault.forcedDepositThreshold(), newThreshold);
    }

    function test_RevertIf_SetForcedDepositThreshold_OutOfBounds() public {
        vm.prank(roles.configurator);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.setForcedDepositThreshold(0);

        uint256 maxDepositBatchSize = vault.maxDepositBatchSize();
        vm.prank(roles.configurator);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.setForcedDepositThreshold(maxDepositBatchSize + 1);
    }

    function test_SetForcedWithdrawThreshold() public {
        uint256 newThreshold = 2_000e18;
        vm.prank(roles.configurator);
        vault.setForcedWithdrawThreshold(newThreshold);
        assertEq(vault.forcedWithdrawThreshold(), newThreshold);
    }

    function test_RevertIf_SetForcedWithdrawThreshold_OutOfBounds() public {
        vm.prank(roles.configurator);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.setForcedWithdrawThreshold(0);
    }

    function test_SetForcedBatchBlockLimit() public {
        uint256 newLimit = 50_000;
        vm.prank(roles.configurator);
        vault.setForcedBatchBlockLimit(newLimit);
        assertEq(vault.forcedBatchBlockLimit(), newLimit);
    }

    function test_RevertIf_SetForcedBatchBlockLimit_OutOfBounds() public {
        vm.prank(roles.configurator);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.setForcedBatchBlockLimit(0);
    }

    function test_SkipDepositBatch_ForcedBatch_BlockLimitNotReached() public {
        vm.prank(roles.configurator);
        vault.setMinDepositAmount(FORCED_DEPOSIT_THRESHOLD);

        _deposit(users.alice, FORCED_DEPOSIT_THRESHOLD + 1);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT - 1);

        vm.prank(roles.operator);
        vault.skipDepositBatch();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.DepositBatchProcessingFinished));
    }

    function test_SkipDepositBatch_BelowForcedThreshold_NoBlockLimitCheck() public {
        vm.prank(roles.configurator);
        vault.setMinDepositAmount(FORCED_DEPOSIT_THRESHOLD - 1);

        _deposit(users.alice, FORCED_DEPOSIT_THRESHOLD - 1);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT);

        vm.prank(roles.operator);
        vault.skipDepositBatch();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.DepositBatchProcessingFinished));
    }

    function test_RevertIf_SkipDepositBatch_ForcedBatch_BlockLimitReached() public {
        vm.prank(roles.configurator);
        vault.setMinDepositAmount(FORCED_DEPOSIT_THRESHOLD);

        _deposit(users.alice, FORCED_DEPOSIT_THRESHOLD + 1);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.CannotSkipForcedBatch.selector);
        vault.skipDepositBatch();
    }

    function test_SkipWithdrawBatch_ForcedBatch_BlockLimitNotReached() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingFinished);

        vm.prank(users.alice);
        vault.withdraw(SHARES_WITHDRAW_PERCENT);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT - 1);

        vm.prank(roles.operator);
        vault.skipWithdrawBatch();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.Idle));
    }

    function test_SkipWithdrawBatch_BelowForcedThreshold_NoBlockLimitCheck() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingFinished);

        vm.prank(users.alice);
        vault.withdraw(SHARES_WITHDRAW_PERCENT - 1);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT);

        vm.prank(roles.operator);
        vault.skipWithdrawBatch();

        assertEq(uint8(vault.status()), uint8(IVault.VaultStatus.Idle));
    }

    function test_RevertIf_SkipWithdrawBatch_ForcedBatch_BlockLimitReached() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingFinished);

        vm.prank(users.alice);
        vault.withdraw(SHARES_WITHDRAW_PERCENT);

        vm.roll(block.number + FORCED_BATCH_BLOCK_LIMIT);

        vm.prank(roles.operator);
        vm.expectRevert(IVault.CannotSkipForcedBatch.selector);
        vault.skipWithdrawBatch();
    }
}
