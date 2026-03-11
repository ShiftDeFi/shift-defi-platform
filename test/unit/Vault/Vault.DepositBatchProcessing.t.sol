// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "contracts/interfaces/IVault.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";

import {L1Base} from "test/L1Base.t.sol";

contract VaultDepositBatchProcessingTest is L1Base {
    using Math for uint256;
    using stdStorage for StdStorage;

    function test_RevertIf_StartDepositBatch_NotInIdleStatus() public {
        stdstore.target(address(vault)).sig(vault.status.selector).checked_write(
            uint256(IVault.VaultStatus.DepositBatchProcessingStarted)
        );
        vm.expectRevert(IVault.IncorrectStatus.selector);
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
    }

    function test_RevertIf_StartDepositBatch_NotEnoughDeposits() public {
        vm.prank(roles.configurator);
        vault.setMinDepositBatchSize(1);

        vm.expectRevert(IVault.DepositBatchSizeTooSmall.selector);
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
    }

    function test_RevertIf_StartDepositBatch_NoContainers() public {
        _deposit(users.alice, DEPOSIT_AMOUNT);

        vm.expectRevert(IVault.NoContainers.selector);
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
    }

    function test_RevertIf_StartDepositBatch_ContainerWeightIsZero() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        uint256 depositAmount = MIN_DEPOSIT_BATCH_SIZE * NOTION_PRECISION;
        _deposit(users.alice, depositAmount);

        vm.expectRevert(abi.encodeWithSelector(IVault.ContainerWeightZero.selector, address(container2)));
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
    }

    function test_StartDepositBatch() public {
        uint256 previousDepositBatchId = vault.depositBatchId();
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        uint256 depositAmount = MIN_DEPOSIT_BATCH_SIZE * NOTION_PRECISION;
        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        assertEq(
            uint256(vault.status()),
            uint256(IVault.VaultStatus.DepositBatchProcessingStarted),
            "test_StartDepositBatch: status"
        );
        assertEq(vault.depositBatchId(), previousDepositBatchId + 1, "test_StartDepositBatch: depositBatchId");
        assertEq(
            vault.depositBatchTotalNotion(previousDepositBatchId),
            depositAmount,
            "test_StartDepositBatch: depositBatchTotalNotion"
        );
        assertEq(vault.bufferedDeposits(), 0, "test_StartDepositBatch: bufferedDeposits");

        assertEq(notion.balanceOf(address(vault)), 0, "test_StartDepositBatch: notionBalanceOfVault");
        assertEq(
            notion.balanceOf(address(container)),
            depositAmount,
            "test_StartDepositBatch: notionBalanceOfContainer"
        );
    }

    function test_StartDepositBatch_ContainerDistribution() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        IContainerPrincipal container3 = _deployMockContainerPrincipal();

        _addContainer(address(container1), REMOTE_CHAIN_ID);
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);
        _addContainer(address(container3), REMOTE_CHAIN_ID + 2);

        uint256 containersCount = 3;

        address[] memory containers = new address[](containersCount);
        containers[0] = address(container1);
        containers[1] = address(container2);
        containers[2] = address(container3);

        uint256[] memory weights = new uint256[](containersCount);
        weights[0] = TOTAL_CONTAINER_WEIGHT / containersCount;
        weights[1] = TOTAL_CONTAINER_WEIGHT / containersCount;
        weights[2] = TOTAL_CONTAINER_WEIGHT - weights[0] - weights[1];

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        uint256 depositAmount = vault.minDepositBatchSize();
        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        uint256 expectedContainerBalance1 = depositAmount.mulDiv(
            _weightForContainer(containers, weights, address(container1)),
            TOTAL_CONTAINER_WEIGHT
        );
        uint256 expectedContainerBalance2 = depositAmount.mulDiv(
            _weightForContainer(containers, weights, address(container2)),
            TOTAL_CONTAINER_WEIGHT
        );
        uint256 expectedContainerBalance3 = depositAmount.mulDiv(
            _weightForContainer(containers, weights, address(container3)),
            TOTAL_CONTAINER_WEIGHT
        );

        assertEq(
            IERC20(notion).balanceOf(address(container1)),
            expectedContainerBalance1,
            "test_StartDepositBatchContainerDistribution: container1 balance"
        );
        assertEq(
            IERC20(notion).balanceOf(address(container2)),
            expectedContainerBalance2,
            "test_StartDepositBatchContainerDistribution: container2 balance"
        );
        assertEq(
            IERC20(notion).balanceOf(address(container3)),
            expectedContainerBalance3,
            "test_StartDepositBatchContainerDistribution: container3 balance"
        );
    }

    function _weightForContainer(
        address[] memory containers,
        uint256[] memory weights,
        address container
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < containers.length; ++i) {
            if (containers[i] == container) return weights[i];
        }
        return 0;
    }

    function test_SkipDepositBatch() public {
        /// @dev Prevent empty vault error
        stdstore.target(address(vault)).sig(IERC20.totalSupply.selector).checked_write(1);

        uint256 previousDepositBatchId = vault.depositBatchId();
        vm.prank(roles.operator);
        vault.skipDepositBatch();

        assertEq(vault.depositBatchId(), previousDepositBatchId, "test_SkipDepositBatch: depositBatchId");
        assertEq(
            uint256(vault.status()),
            uint256(IVault.VaultStatus.DepositBatchProcessingFinished),
            "test_SkipDepositBatch: status"
        );
    }

    function test_RevertIf_SkipDepositBatch_NotInIdleStatus() public {
        stdstore.target(address(vault)).sig(vault.status.selector).checked_write(
            uint256(IVault.VaultStatus.DepositBatchProcessingStarted)
        );
        vm.expectRevert(IVault.IncorrectBatchStatus.selector);
        vm.prank(roles.operator);
        vault.skipDepositBatch();
    }

    function test_RevertIf_SkipDepositBatch_EmptyVault() public {
        vm.expectRevert(IVault.CannotSkipBatchInEmptyVault.selector);
        vm.prank(roles.operator);
        vault.skipDepositBatch();
    }

    function test_RevertIf_SkipDepositBatch_WithEnoughDeposits() public {
        /// @dev Prevent empty vault error
        stdstore.target(address(vault)).sig(IERC20.totalSupply.selector).checked_write(1);
        _deposit(users.alice, vault.minDepositBatchSize());

        vm.expectRevert(IVault.CannotSkipBatch.selector);
        vm.prank(roles.operator);
        vault.skipDepositBatch();
    }
}
