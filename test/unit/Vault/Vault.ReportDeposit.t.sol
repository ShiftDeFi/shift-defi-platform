// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

contract VaultReportDepositTest is VaultBaseTest {
    function test_ReportDeposit() public {
        uint256 depositBatchId = vault.depositBatchId();

        _deposit(users.alice, DEPOSIT_AMOUNT);
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (address[] memory containers, ) = vault.getContainers();

        for (uint256 i = 0; i < containers.length; i++) {
            uint256 nav0 = vm.randomUint(1e18, 5000e18);
            uint256 nav1 = vm.randomUint(nav0 + 1, 10000e18);

            uint256 notionRemainder = vm.randomUint(1e6, 100000e6);
            notion.mint(containers[i], notionRemainder);

            vm.prank(containers[i]);
            notion.approve(address(vault), notionRemainder);

            uint256 notionAmountBefore = notion.balanceOf(address(vault));

            vm.prank(containers[i]);
            vault.reportDeposit(IVault.ContainerReport({nav0: nav0, nav1: nav1}), notionRemainder);

            vm.assertEq(
                notion.balanceOf(address(vault)),
                notionAmountBefore + notionRemainder,
                "test_ReportDeposit: vault notion balance mismatch"
            );
            vm.assertEq(
                vault.batchNotionRemainder(depositBatchId),
                notionAmountBefore + notionRemainder,
                "test_ReportDeposit: batch notion remainder mismatch"
            );
            vm.assertEq(
                vault.totalUnclaimedNotionRemainder(),
                notionAmountBefore + notionRemainder,
                "test_ReportDeposit: total unclaimed remainder mismatch"
            );

            if (i == containers.length - 1) {
                vm.assertEq(vault.isDepositReportComplete(), true, "test_ReportDeposit: report should be complete");
            } else {
                vm.assertEq(
                    vault.isDepositReportComplete(),
                    false,
                    "test_ReportDeposit: report should not be complete"
                );
            }
        }

        assertEq(
            uint256(vault.status()),
            uint256(IVault.VaultStatus.DepositBatchProcessingStarted),
            "test_ReportDeposit: status mismatch"
        );
    }

    function test_RevertIf_ReportDeposit_NotContainer() public {
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(IVault.NotContainer.selector, users.alice));
        vault.reportDeposit(IVault.ContainerReport({nav0: 0, nav1: 0}), 0);
    }

    function test_RevertIf_ReportDeposit_NotInDepositBatchProcessingStartedStatus() public {
        (address[] memory containers, ) = vault.getContainers();
        vm.prank(containers[0]);
        vm.expectRevert(IVault.IncorrectStatus.selector);
        vault.reportDeposit(IVault.ContainerReport({nav0: 0, nav1: 0}), 0);
    }

    function test_RevertIf_ReportDeposit_nav1LessThanNav0() public {
        uint256 nav1 = vm.randomUint(1e18, 5000e18);
        uint256 nav0 = vm.randomUint(nav1 + 1, 10000e18);
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);
        (address[] memory containers, ) = vault.getContainers();
        vm.prank(containers[0]);
        vm.expectRevert(IVault.IncorrectReport.selector);
        vault.reportDeposit(IVault.ContainerReport({nav0: nav0, nav1: nav1}), 0);
    }

    function test_RevertIf_ReportDeposit_ContainerAlreadyReported() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);

        (address[] memory containers, ) = vault.getContainers();

        vm.prank(containers[0]);
        vault.reportDeposit(IVault.ContainerReport({nav0: 0, nav1: 0}), 0);

        vm.prank(containers[0]);
        vm.expectRevert(IVault.ContainerAlreadyReported.selector);
        vault.reportDeposit(IVault.ContainerReport({nav0: 0, nav1: 0}), 0);
    }

    function test_RevertIf_ReportDeposit_NotionRemainderNotEnough() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);

        uint256 notionRemainder = vm.randomUint(1e6, 100000e6);

        (address[] memory containers, ) = vault.getContainers();

        vm.prank(containers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, containers[0], 0, notionRemainder)
        );
        vault.reportDeposit(IVault.ContainerReport({nav0: 0, nav1: 0}), notionRemainder);
    }
}
