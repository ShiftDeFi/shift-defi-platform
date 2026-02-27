// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "contracts/interfaces/IVault.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";

contract VaultResolveDepositBatchTest is VaultBaseTest {
    using Math for uint256;

    function test_ResolveDepositBatch_IfNavDeltaIsZero() public {
        uint256 depositBatchId = vault.depositBatchId();
        uint256 depositAmount = vm.randomUint(vault.minDepositAmount(), vault.maxDepositAmount());

        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        _reportDepositBatchAllContainersOnlyNotion(depositAmount);

        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        vm.assertEq(
            vault.lastResolvedDepositBatchId(),
            depositBatchId,
            "test_ResolveDepositBatch_IfNavDeltaIsZero: last resolved batch id mismatch"
        );
        vm.assertEq(
            vault.depositBatchTotalShares(depositBatchId),
            0,
            "test_ResolveDepositBatch_IfNavDeltaIsZero: deposit batch total shares should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).totalSupply(),
            0,
            "test_ResolveDepositBatch_IfNavDeltaIsZero: total supply should be zero"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            0,
            "test_ResolveDepositBatch_IfNavDeltaIsZero: vault balance should be zero"
        );
    }

    function test_ResolveDepositBatch_IfTotalSupplyIsZero() public {
        uint256 depositBatchId = vault.depositBatchId();
        uint256 depositAmount = vm.randomUint(vault.minDepositAmount(), vault.maxDepositAmount());

        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (uint256 totalAmount, uint256 totalRemainder) = _reportDepositBatchAllContainersWithRemainder(depositAmount);

        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        uint256 navDelta = totalAmount - totalRemainder;

        vm.assertEq(
            uint8(vault.status()),
            uint8(IVault.VaultStatus.DepositBatchProcessingFinished),
            "test_ResolveDepositBatch_IfTotalSupplyIsZero: status mismatch"
        );
        vm.assertEq(
            vault.lastResolvedDepositBatchId(),
            depositBatchId,
            "test_ResolveDepositBatch_IfTotalSupplyIsZero: last resolved batch id mismatch"
        );
        vm.assertEq(
            vault.depositBatchTotalShares(depositBatchId),
            navDelta,
            "test_ResolveDepositBatch_IfTotalSupplyIsZero: deposit batch total shares mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).totalSupply(),
            navDelta,
            "test_ResolveDepositBatch_IfTotalSupplyIsZero: total supply mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            navDelta,
            "test_ResolveDepositBatch_IfTotalSupplyIsZero: vault balance mismatch"
        );
    }

    function test_ResolveDepositBatch() public {
        _deposit(users.alice, DEPOSIT_AMOUNT);
        uint256 resolvedBatchId = _processResolvedDepositBatch();

        uint256 batchShares = vault.depositBatchTotalShares(resolvedBatchId);

        vm.assertEq(
            uint8(vault.status()),
            uint8(IVault.VaultStatus.DepositBatchProcessingFinished),
            "test_ResolveDepositBatch: status mismatch"
        );
        vm.assertEq(
            vault.lastResolvedDepositBatchId(),
            resolvedBatchId,
            "test_ResolveDepositBatch: last resolved batch id mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).totalSupply(),
            batchShares,
            "test_ResolveDepositBatch: total supply mismatch"
        );
        vm.assertEq(
            IERC20(address(vault)).balanceOf(address(vault)),
            batchShares,
            "test_ResolveDepositBatch: vault balance mismatch"
        );
    }

    function test_RevertIf_ResolveDepositBatch_IncorrectStatus() public {
        vm.expectRevert(IVault.IncorrectBatchStatus.selector);
        vm.prank(roles.operator);
        vault.resolveDepositBatch();
    }

    function test_RevertIf_ResolveDepositBatch_MissingContainerReport() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);
        vm.expectRevert(IVault.MissingContainerReport.selector);
        vm.prank(roles.operator);
        vault.resolveDepositBatch();
    }
}
