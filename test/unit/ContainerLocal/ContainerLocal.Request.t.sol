// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ContainerLocalBaseTest} from "test/unit/ContainerLocal/ContainerLocalBase.t.sol";
import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

contract ContainerLocalRequestTest is ContainerLocalBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_RegisterDepositRequest() public {
        uint256 depositAmount = vault.minDepositAmount();
        _deposit(users.alice, depositAmount);

        vm.prank(address(vault));
        containerLocal.registerDepositRequest(depositAmount);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered)
        );
        assertEq(
            notion.balanceOf(address(containerLocal)),
            depositAmount,
            "test_RegisterDepositRequest: balance mismatch"
        );
    }

    function test_RevertIf_StatusNotIdleAndRegisterDepositRequest() public {
        uint256 depositAmount = vault.minDepositAmount();
        _deposit(users.alice, depositAmount);

        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);

        vm.prank(address(vault));
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerLocal.registerDepositRequest(depositAmount);
    }

    function test_RevertIf_ZeroAmountAndRegisterDepositRequest() public {
        uint256 depositAmount = 0;

        vm.prank(address(vault));
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerLocal.registerDepositRequest(depositAmount);
    }

    function test_RegisterWithdrawRequest() public {
        uint256 amount = vault.minWithdrawBatchRatio();

        vm.prank(address(vault));
        containerLocal.registerWithdrawRequest(amount);

        assertEq(
            uint256(containerLocal.status()),
            uint256(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered)
        );
        assertEq(
            containerLocal.registeredWithdrawShareAmount(),
            amount,
            "test_RegisterWithdrawRequest: registeredWithdrawShareAmount mismatch"
        );
    }

    function test_RevertIf_StatusNotIdleAndRegisterWithdrawRequest() public {
        uint256 withdrawShareAmount = vault.minWithdrawBatchRatio();

        _setContainerStatus(IContainerLocal.ContainerLocalStatus.WithdrawalRequestRegistered);

        vm.prank(address(vault));
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerLocal.registerWithdrawRequest(withdrawShareAmount);
    }

    function test_RevertIf_ZeroAmountAndRegisterWithdrawRequest() public {
        uint256 withdrawShareAmount = 0;

        vm.prank(address(vault));
        vm.expectRevert(Errors.ZeroAmount.selector);
        containerLocal.registerWithdrawRequest(withdrawShareAmount);
    }

    function test_ReportDeposit() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered);
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);

        vm.prank(roles.operator);
        containerLocal.reportDeposit();

        assertEq(uint256(containerLocal.status()), uint256(IContainerLocal.ContainerLocalStatus.Idle));
    }

    function test_RevertIf_StatusNotAllStrategiesEnteredAndReportDeposit() public {
        vm.prank(roles.operator);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerLocal.reportDeposit();
    }

    function test_ReportWithdraw() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.AllStrategiesExited);
        _setVaultStatus(IVault.VaultStatus.WithdrawBatchProcessingStarted);
        deal(address(notion), address(containerLocal), 1);

        vm.prank(roles.operator);
        containerLocal.reportWithdraw();

        assertEq(uint256(containerLocal.status()), uint256(IContainerLocal.ContainerLocalStatus.Idle));
        assertEq(
            containerLocal.registeredWithdrawShareAmount(),
            0,
            "test_ReportWithdraw: registeredWithdrawShareAmount mismatch"
        );
    }

    function test_RevertIf_StatusNotAllStrategiesExitedAndReportWithdraw() public {
        vm.prank(roles.operator);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        containerLocal.reportWithdraw();
    }
}
