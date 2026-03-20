// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IVault} from "contracts/interfaces/IVault.sol";

import {L1Base} from "test/L1Base.t.sol";

contract VaultLimitsTest is L1Base {
    function test_RevertIf_MaxDepositAmountGreaterThanMaxDepositBatchSize() public {
        uint256 maxDepositBatchSize = vault.maxDepositBatchSize();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMaxDepositAmount.selector);
        vault.setMaxDepositAmount(maxDepositBatchSize + 1);
    }

    function test_RevertIf_MaxDepositAmountLessThanMinDepositAmount() public {
        uint256 minDepositAmount = vault.minDepositAmount();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMaxDepositAmount.selector);
        vault.setMaxDepositAmount(minDepositAmount - 1);
    }

    function test_RevertIf_MinDepositAmountGreaterThanMaxDepositAmount() public {
        uint256 maxDepositAmount = vault.maxDepositAmount();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMinDepositAmount.selector);
        vault.setMinDepositAmount(maxDepositAmount + 1);
    }

    function test_RevertIf_MaxDepositBatchSizeLessThanOrEqualToMinDepositBatchSize() public {
        uint256 minDepositBatchSize = vault.minDepositBatchSize();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMaxDepositBatchSize.selector);
        vault.setMaxDepositBatchSize(minDepositBatchSize);
    }

    function test_RevertIf_MaxDepositBatchSizeGreaterThanMaxDepositAmount() public {
        uint256 maxDepositAmount = vault.maxDepositAmount();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMaxDepositBatchSize.selector);
        vault.setMaxDepositBatchSize(maxDepositAmount - 1);
    }

    function test_RevertIf_MinDepositBatchSizeGreaterThanOrEqualToMaxDepositBatchSize() public {
        uint256 maxDepositBatchSize = vault.maxDepositBatchSize();
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMinDepositBatchSize.selector);
        vault.setMinDepositBatchSize(maxDepositBatchSize);
    }

    function test_RevertIf_MinWithdrawBatchRatioGreaterThanToMaxBPS() public {
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMinWithdrawBatchRatio.selector);
        vault.setMinWithdrawBatchRatio(MAX_BPS + 1);
    }

    function test_RevertIf_MinWithdrawBatchRatioLessThanOrEqualTo0() public {
        vm.prank(roles.configurator);
        vm.expectRevert(IVault.IncorrectMinWithdrawBatchRatio.selector);
        vault.setMinWithdrawBatchRatio(0);
    }
}
