// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

contract VaultReportWithdrawTest is VaultBaseTest {
    function setUp() public override {
        super.setUp();
        _setVaultStatus(IVault.VaultStatus.WithdrawBatchProcessingStarted);
    }

    function test_ReportWithdraw() public {
        uint256 previousWithdrawBatchId = vault.withdrawBatchId() - 1;

        (address[] memory containers, ) = vault.getContainers();
        for (uint256 i = 0; i < containers.length; i++) {
            uint256 notionAmount = vm.randomUint(1e6, 100000e6);
            notion.mint(containers[i], notionAmount);

            uint256 notionAmountBefore = notion.balanceOf(address(vault));
            vm.prank(containers[i]);
            vault.reportWithdraw(notionAmount);

            uint256 accruedNotionAmount = notionAmountBefore + notionAmount;

            vm.assertEq(
                vault.withdrawBatchTotalNotion(previousWithdrawBatchId),
                accruedNotionAmount,
                "test_ReportWithdraw: withdraw batch total notion mismatch"
            );
            vm.assertEq(
                vault.totalUnclaimedNotionForWithdraw(),
                accruedNotionAmount,
                "test_ReportWithdraw: total unclaimed notion mismatch"
            );
            vm.assertEq(
                notion.balanceOf(address(vault)),
                accruedNotionAmount,
                "test_ReportWithdraw: vault notion balance mismatch"
            );

            if (i == containers.length - 1) {
                vm.assertEq(vault.isWithdrawReportComplete(), true, "test_ReportWithdraw: report should be complete");
            } else {
                vm.assertEq(
                    vault.isWithdrawReportComplete(),
                    false,
                    "test_ReportWithdraw: report should not be complete"
                );
            }
        }

        assertEq(
            uint256(vault.status()),
            uint256(IVault.VaultStatus.WithdrawBatchProcessingStarted),
            "test_ReportWithdraw: status mismatch"
        );
    }

    function test_RevertIf_ReportWithdraw_NotContainer() public {
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(IVault.NotContainer.selector, users.alice));
        vault.reportWithdraw(1000 * 1e18);
    }

    function test_RevertIf_ReportWithdraw_ContainerAlreadyReported() public {
        (address[] memory containers, ) = vault.getContainers();

        uint256 notionAmount = vm.randomUint(1e6, 100000e6);
        notion.mint(containers[0], notionAmount);

        vm.prank(containers[0]);
        vault.reportWithdraw(notionAmount);

        vm.prank(containers[0]);
        vm.expectRevert(abi.encodeWithSelector(IVault.ContainerAlreadyReported.selector, containers[0]));
        vault.reportWithdraw(notionAmount);
    }
}
