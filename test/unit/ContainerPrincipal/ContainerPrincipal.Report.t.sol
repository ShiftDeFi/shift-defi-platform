// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVault} from "contracts/interfaces/IVault.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {Common} from "contracts/libraries/Common.sol";

import {ContainerPrincipalBaseTest} from "test/unit/ContainerPrincipal/ContainerPrincipalBase.t.sol";

contract ContainerPrincipalReportTest is ContainerPrincipalBaseTest {
    bytes32 private constant DEPOSIT_REPORTS_SLOT = bytes32(uint256(15));
    bytes32 private constant DEPOSIT_REPORT_BITMASK_SLOT = bytes32(uint256(16));
    bytes32 private constant WITHDRAW_REPORT_BITMASK_SLOT = bytes32(uint256(24));
    error ContainerNotFound();

    function setUp() public override {
        super.setUp();
    }

    function _prepareToReportDepositSingleToken(
        address token,
        uint256 remainderAmount,
        uint256 nav0,
        uint256 nav1
    ) internal {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.DepositRequestSent);

        bytes memory message = _craftDepositResponseMessageSingleToken(token, remainderAmount, nav0, nav1);

        if (remainderAmount > 0) {
            bridgeAdapter.finalizeBridge(address(containerPrincipal), token, remainderAmount);
        }

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);
    }

    function _prepareToReportWithdrawalSingleToken(address token, uint256 withdrawnAmount, bool doClaim) internal {
        vm.prank(address(vault));
        containerPrincipal.registerWithdrawRequest(withdrawnAmount);

        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.WithdrawalRequestSent);

        bytes memory message = _craftWithdrawalResponseMessageSingleToken(token, withdrawnAmount);

        vm.prank(address(messageRouter));
        containerPrincipal.receiveMessage(message);

        if (doClaim) {
            MockERC20(token).mint(address(bridgeAdapter), withdrawnAmount);
            bridgeAdapter.finalizeBridge(address(containerPrincipal), token, withdrawnAmount);
            vm.prank(roles.operator);
            containerPrincipal.claim(address(bridgeAdapter), token);
        }

        _setVaultStatus(IVault.VaultStatus.WithdrawBatchProcessingStarted);
    }

    function _getContainerIndex(address container) internal view returns (uint256) {
        (address[] memory containers, ) = vault.getContainers();

        for (uint256 i = 0; i < containers.length; i++) {
            if (containers[i] == container) {
                return i;
            }
        }

        revert ContainerNotFound();
    }

    function test_ReportDepositWithoutRemainder() public {
        uint256 depositBatchSize = vault.maxDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize;
        uint256 remainderAmount = depositBatchSize - nav1;
        _prepareToReportDepositSingleToken(address(0), remainderAmount, nav0, nav1);

        vm.prank(roles.operator);
        containerPrincipal.reportDeposit();

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.Idle),
            "test_ReportDepositWithoutRemainder: status mismatch"
        );

        uint256 containerIndex = _getContainerIndex(address(containerPrincipal));
        uint256 depositReportBitmask = uint256(vm.load(address(vault), DEPOSIT_REPORT_BITMASK_SLOT));
        assertTrue(
            depositReportBitmask & (1 << containerIndex) != 0,
            "test_ReportDepositWithoutRemainder: deposit report bitmask mismatch"
        );

        bytes32 baseSlot = keccak256(abi.encode(address(containerPrincipal), DEPOSIT_REPORTS_SLOT));

        uint256 nav0Value = uint256(vm.load(address(vault), baseSlot));
        uint256 nav1Value = uint256(vm.load(address(vault), bytes32(uint256(baseSlot) + 1)));

        assertEq(
            nav0Value,
            Common.toUnifiedDecimalsUint8(address(notion), nav0),
            "test_ReportDepositWithoutRemainder: nav0 value mismatch"
        );
        assertEq(
            nav1Value,
            Common.toUnifiedDecimalsUint8(address(notion), nav1),
            "test_ReportDepositWithoutRemainder: nav1 value mismatch"
        );

        assertEq(containerPrincipal.claimCounter(), 0, "test_ReportDepositWithoutRemainder: claim counter mismatch");
    }

    function test_ReportDepositWithRemainder() public {
        uint256 depositBatchSize = vault.maxDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainderAmount = depositBatchSize - nav1;
        _prepareToReportDepositSingleToken(address(notion), remainderAmount, nav0, nav1);

        assertEq(containerPrincipal.claimCounter(), 1, "test_ReportDeposit: claim counter mismatch");

        notion.mint(address(bridgeAdapter), remainderAmount);

        vm.startPrank(roles.operator);
        containerPrincipal.claim(address(bridgeAdapter), address(notion));
        containerPrincipal.reportDeposit();
        vm.stopPrank();

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.Idle),
            "test_ReportDepositWithRemainder: status mismatch"
        );

        uint256 containerIndex = _getContainerIndex(address(containerPrincipal));
        uint256 depositReportBitmask = uint256(vm.load(address(vault), DEPOSIT_REPORT_BITMASK_SLOT));
        assertTrue(
            depositReportBitmask & (1 << containerIndex) != 0,
            "test_ReportDepositWithRemainder: deposit report bitmask mismatch"
        );

        bytes32 baseSlot = keccak256(abi.encode(address(containerPrincipal), DEPOSIT_REPORTS_SLOT));

        uint256 nav0Value = uint256(vm.load(address(vault), baseSlot));
        uint256 nav1Value = uint256(vm.load(address(vault), bytes32(uint256(baseSlot) + 1)));

        assertEq(
            nav0Value,
            Common.toUnifiedDecimalsUint8(address(notion), nav0),
            "test_ReportDepositWithRemainder: nav0 value mismatch"
        );
        assertEq(
            nav1Value,
            Common.toUnifiedDecimalsUint8(address(notion), nav1),
            "test_ReportDepositWithRemainder: nav1 value mismatch"
        );

        assertEq(
            IERC20(notion).balanceOf(address(vault)),
            remainderAmount,
            "test_ReportDepositWithRemainder: notion balance mismatch"
        );
    }

    function test_RevertIf_ReportDepositWithStatusNotBridgeClaimedOrDepositResponseReceived() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerPrincipal.reportDeposit();
    }

    function test_RevertIf_ReportDepositWithClaimCounterNotZero() public {
        uint256 depositBatchSize = vault.maxDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainderAmount = depositBatchSize - nav1;
        _prepareToReportDepositSingleToken(address(notion), remainderAmount, nav0, nav1);

        vm.prank(roles.operator);
        vm.expectRevert(ICrossChainContainer.UnclaimedTokens.selector);
        containerPrincipal.reportDeposit();
    }

    function test_RevertIf_ReportDepositWithWhitelistedTokensOnBalance() public {
        uint256 depositBatchSize = vault.maxDepositBatchSize();
        uint256 nav0 = 0;
        uint256 nav1 = depositBatchSize / 2;
        uint256 remainderAmount = depositBatchSize - nav1;

        _whitelistToken(address(containerPrincipal), address(dai));
        _prepareToReportDepositSingleToken(address(dai), remainderAmount, nav0, nav1);

        dai.mint(address(bridgeAdapter), remainderAmount);
        vm.prank(roles.operator);
        containerPrincipal.claim(address(bridgeAdapter), address(dai));

        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IContainer.WhitelistedTokensOnBalance.selector, address(dai)));
        containerPrincipal.reportDeposit();
    }

    function test_ReportWithdrawal() public {
        uint256 withdrawBatchSize = vault.minDepositBatchSize();
        _prepareToReportWithdrawalSingleToken(address(notion), withdrawBatchSize, true);

        uint256 previousBatchId = vault.withdrawBatchId() - 1;
        uint256 withdrawBatchTotalNotionBefore = vault.withdrawBatchTotalNotion(previousBatchId);
        uint256 totalUnclaimedNotionForWithdrawBefore = vault.totalUnclaimedNotionForWithdraw();

        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();

        assertEq(
            uint256(containerPrincipal.status()),
            uint256(IContainerPrincipal.ContainerPrincipalStatus.Idle),
            "test_ReportWithdrawal: status mismatch"
        );

        assertEq(
            containerPrincipal.registeredWithdrawShareAmount(),
            0,
            "test_ReportWithdrawal: registered withdraw share amount mismatch"
        );

        uint256 containerIndex = _getContainerIndex(address(containerPrincipal));
        uint256 withdrawReportBitmask = uint256(vm.load(address(vault), WITHDRAW_REPORT_BITMASK_SLOT));
        assertTrue(
            withdrawReportBitmask & (1 << containerIndex) != 0,
            "test_ReportWithdrawal: withdraw report bitmask mismatch"
        );

        assertEq(
            withdrawBatchTotalNotionBefore + withdrawBatchSize,
            vault.withdrawBatchTotalNotion(previousBatchId),
            "test_ReportWithdrawal: withdraw batch total notion mismatch"
        );

        assertEq(
            totalUnclaimedNotionForWithdrawBefore + withdrawBatchSize,
            vault.totalUnclaimedNotionForWithdraw(),
            "test_ReportWithdrawal: total unclaimed notion for withdraw mismatch"
        );

        assertEq(
            IERC20(notion).balanceOf(address(vault)),
            withdrawBatchSize,
            "test_ReportWithdrawal: notion balance mismatch"
        );
    }

    function test_RevertIf_ReportWithdrawalWithStatusNotBridgeClaimed() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.Idle);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();
    }

    function test_RevertIf_ReportWithdrawalWithRegisteredWithdrawShareAmountZero() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();
    }

    function test_RevertIf_ReportWithdrawalWithClaimCounterNotZero() public {
        _prepareToReportWithdrawalSingleToken(address(notion), vault.minDepositBatchSize(), false);
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed);

        vm.expectRevert(ICrossChainContainer.UnclaimedTokens.selector);
        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();
    }

    function test_RevertIf_ReportWithdrawalWithWhitelistedTokensOnBalance() public {
        _prepareToReportWithdrawalSingleToken(address(notion), vault.minDepositBatchSize(), true);

        _whitelistToken(address(containerPrincipal), address(dai));
        dai.mint(address(containerPrincipal), vault.minDepositBatchSize());

        vm.expectRevert(abi.encodeWithSelector(IContainer.WhitelistedTokensOnBalance.selector, address(notion)));
        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();
    }
}
