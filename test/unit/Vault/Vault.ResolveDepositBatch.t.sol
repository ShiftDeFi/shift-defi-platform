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
        vm.expectRevert(abi.encodeWithSelector(IVault.IncorrectVaultStatus.selector, IVault.VaultStatus.Idle));
        vm.prank(roles.operator);
        vault.resolveDepositBatch();
    }

    function test_RevertIf_ResolveDepositBatch_MissingContainerReport() public {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);
        vm.expectRevert(IVault.MissingContainerReport.selector);
        vm.prank(roles.operator);
        vault.resolveDepositBatch();
    }

    function test_ResolveDepositBatch_PendingBurnShares() public {
        uint256 _depositAmount = 1_000 * 1e6;

        vm.prank(roles.configurator);
        vault.setMinDepositAmount(_depositAmount);
        vm.prank(roles.configurator);
        vault.setMinDepositBatchSize(_depositAmount);

        _deposit(users.alice, _depositAmount);
        _deposit(users.bob, _depositAmount);
        _deposit(users.charlie, _depositAmount);
        _deposit(users.david, _depositAmount);
        _deposit(users.eve, _depositAmount);
        _deposit(users.francis, 5 * _depositAmount);

        uint256 totalDeposit = 10 * _depositAmount;

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            uint256 amount = (totalDeposit * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            _reportDepositBatch(containers[i], 0, amount, 0);
        }
        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        vm.prank(users.alice);
        vault.claimDeposit(1, users.alice);

        vm.prank(users.bob);
        vault.claimDeposit(1, users.bob);

        vm.prank(users.charlie);
        vault.claimDeposit(1, users.charlie);

        vm.prank(users.david);
        vault.claimDeposit(1, users.david);

        vm.prank(users.eve);
        vault.claimDeposit(1, users.eve);

        vm.prank(users.francis);
        vault.claimDeposit(1, users.francis);

        vm.startPrank(users.alice);
        IERC20(address(vault)).approve(address(vault), _depositAmount);
        vault.withdraw(MAX_BPS);
        vm.stopPrank();

        vm.startPrank(users.bob);
        IERC20(address(vault)).approve(address(vault), _depositAmount);
        vault.withdraw(MAX_BPS);
        vm.stopPrank();

        vm.startPrank(users.charlie);
        IERC20(address(vault)).approve(address(vault), _depositAmount);
        vault.withdraw(MAX_BPS);
        vm.stopPrank();

        vm.startPrank(users.david);
        IERC20(address(vault)).approve(address(vault), _depositAmount);
        vault.withdraw(MAX_BPS);
        vm.stopPrank();

        vm.startPrank(users.eve);
        IERC20(address(vault)).approve(address(vault), _depositAmount);
        vault.withdraw(MAX_BPS);
        vm.stopPrank();

        uint256 totalWithdrawnAmount = 5 * _depositAmount;

        vm.prank(roles.operator);
        vault.startWithdrawBatchProcessing();

        for (uint256 i = 0; i < containers.length; ++i) {
            uint256 containerReportedNotionAmount = totalWithdrawnAmount.mulDiv(weights[i], TOTAL_CONTAINER_WEIGHT);
            notion.mint(containers[i], containerReportedNotionAmount);
            vm.startPrank(containers[i]);
            IERC20(address(notion)).approve(address(vault), containerReportedNotionAmount);
            vault.reportWithdraw(containerReportedNotionAmount);
            vm.stopPrank();
        }

        vm.prank(roles.operator);
        vault.resolveWithdrawBatch();

        uint256 georgeDeposit = 5 * _depositAmount;

        vm.prank(roles.configurator);
        vault.setMaxDepositAmount(georgeDeposit);

        _deposit(users.george, georgeDeposit);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        uint256 totalNav0 = totalDeposit - totalWithdrawnAmount;

        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            uint256 amount = (totalDeposit * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            _reportDepositBatch(containers[i], totalNav0.mulDiv(weights[i], TOTAL_CONTAINER_WEIGHT), amount, 0);
        }

        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        vm.prank(users.george);
        vault.claimDeposit(2, users.george);

        assertEq(IERC20(address(vault)).balanceOf(users.george), georgeDeposit);
    }
}
