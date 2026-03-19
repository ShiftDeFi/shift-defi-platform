// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

contract VaultResolveWithdrawBatchTest is VaultBaseTest {
    function setUp() public override {
        super.setUp();
        _setVaultStatus(IVault.VaultStatus.WithdrawBatchProcessingStarted);
    }

    function test_ResolveWithdrawBatch() public {
        uint256 previousWithdrawBatchId = vault.withdrawBatchId();
        _processSingleUserResolvedWithdrawBatch(users.alice);

        vm.assertEq(
            uint8(vault.status()),
            uint8(IVault.VaultStatus.Idle),
            "test_ResolveWithdrawBatch: status should be Idle"
        );
        vm.assertEq(
            vault.lastResolvedWithdrawBatchId(),
            previousWithdrawBatchId,
            "test_ResolveWithdrawBatch: last resolved withdraw batch id mismatch"
        );
    }

    function test_RevertIf_ResolveWithdrawBatch_IncorrectStatus() public {
        _setVaultStatus(IVault.VaultStatus.Idle);
        vm.expectRevert(IVault.IncorrectVaultStatus.selector);
        vm.prank(roles.operator);
        vault.resolveWithdrawBatch();
    }

    function test_RevertIf_ResolveWithdrawBatch_MissingContainerReport() public {
        vm.expectRevert(IVault.MissingContainerReport.selector);
        vm.prank(roles.operator);
        vault.resolveWithdrawBatch();
    }

    function test_RevertIf_ResolveWithdrawBatch_NotOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, users.alice, OPERATOR_ROLE)
        );
        vm.prank(users.alice);
        vault.resolveWithdrawBatch();
    }
}
