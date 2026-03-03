// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {L1Base} from "test/L1Base.t.sol";

import {IVault} from "contracts/interfaces/IVault.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract VaultBaseTest is L1Base {
    using stdStorage for StdStorage;
    using Math for uint256;

    uint256 internal vaultPrecision;

    uint256 internal constant DEFAULT_SHARES_AMOUNT = 1000 * 1e18;
    uint256 internal constant DEFAULT_SHARES_PERCENT = 0.5e18; // 50%
    uint256 internal constant DEFAULT_NOTION_AMOUNT = 100e18;
    uint256 internal constant MAX_CONTAINERS = 255;
    uint256 internal constant REMAINDER_PCT = 0.01e18; // 1%

    uint256 internal constant N_CONTAINERS = 4;

    function setUp() public virtual override {
        super.setUp();
        vaultPrecision = 10 ** uint256(IERC20Metadata(address(vault)).decimals());
        _setupNContainers(N_CONTAINERS);
    }

    function _setupNContainers(uint256 nContainers) internal {
        for (uint i = 0; i < nContainers; i++) {
            address container = address(_deployMockContainerPrincipal());
            _addContainer(container);
            vm.prank(container);
            notion.approve(address(vault), type(uint256).max);
        }

        _setVaultContainerWeightsProportionally();
    }

    function _processSingleUserResolvedWithdrawBatch(address user) internal returns (uint256 withdrawBatchId) {
        uint256 sharesAmount = vm.randomUint(vaultPrecision, 1_000 * vaultPrecision);
        uint256 sharesPct = vm.randomUint(vault.minWithdrawBatchRatio(), MAX_BPS);

        _giveUserShares(user, sharesAmount);
        vm.prank(user);
        vault.withdraw(sharesPct);

        return _processResolvedWithdrawBatch();
    }

    function _processResolvedWithdrawBatch() internal returns (uint256 withdrawBatchId) {
        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingFinished);

        vm.prank(roles.operator);
        vault.startWithdrawBatchProcessing();

        _reportWithdrawBatch();

        vm.prank(roles.operator);
        vault.resolveWithdrawBatch();

        return vault.lastResolvedWithdrawBatchId();
    }

    function _reportWithdrawBatch() public {
        uint256 withdrawnAmount = vm.randomUint(1e6, 100000e18);

        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < containers.length; i++) {
            uint256 containerReportedNotionAmount = (withdrawnAmount * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            notion.mint(containers[i], containerReportedNotionAmount);
            vm.prank(containers[i]);
            vault.reportWithdraw(containerReportedNotionAmount);
        }
    }

    function _processResolvedDepositBatch() internal returns (uint256 depositBatchId) {
        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        uint256 totalDeposit = IERC20(address(notion)).balanceOf(address(vault));

        _reportDepositBatchAllContainersWithRemainder(totalDeposit);

        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        return vault.lastResolvedDepositBatchId();
    }

    function _calculateExpectedNotion(uint256 withdrawBatchId, address user) internal view returns (uint256) {
        uint256 withdrawnShares = vault.pendingBatchWithdrawals(withdrawBatchId, user);
        return
            withdrawnShares.mulDiv(
                vault.withdrawBatchTotalNotion(withdrawBatchId),
                vault.withdrawBatchTotalShares(withdrawBatchId)
            );
    }

    function _reportDepositBatchAllContainersWithRemainder(uint256 depositAmount) internal returns (uint256, uint256) {
        uint256 totalAmount;
        uint256 totalRemainder;

        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            uint256 amount = (depositAmount * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            uint256 remainder = (amount * REMAINDER_PCT) / MAX_BPS;
            _reportDepositBatch(containers[i], 0, amount - remainder, remainder);

            totalAmount += amount;
            totalRemainder += remainder;
        }

        return (totalAmount, totalRemainder);
    }

    function _reportDepositBatchAllContainersOnlyNotion(uint256 depositAmount) internal {
        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            uint256 amount = (depositAmount * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            _reportDepositBatch(containers[i], 0, 0, amount);
        }
    }

    function _reportDepositBatchAllContainersWithoutRemainder(uint256 depositAmount) internal {
        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            uint256 amount = (depositAmount * weights[i]) / TOTAL_CONTAINER_WEIGHT;
            _reportDepositBatch(containers[i], 0, amount, 0);
        }
    }

    function _reportDepositBatchAllContainersEmpty() internal {
        (address[] memory containers, ) = vault.getContainers();
        for (uint256 i = 0; i < N_CONTAINERS; i++) {
            _reportDepositBatch(containers[i], 0, 0, 0);
        }
    }

    function _resolveDepositBatch() internal {
        vm.prank(roles.operator);
        vault.resolveDepositBatch();
    }

    function _setVaultContainerWeightsProportionally() internal {
        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        for (uint256 i = 0; i < containers.length; i++) {
            weights[i] = TOTAL_CONTAINER_WEIGHT / containers.length;
        }
        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function _giveUserShares(address user, uint256 sharesAmount) internal {
        uint256 currentBalance = IERC20(address(vault)).balanceOf(user);
        stdstore.target(address(vault)).sig(IERC20.balanceOf.selector).with_key(user).checked_write(
            currentBalance + sharesAmount
        );
        uint256 currentTotalSupply = IERC20(address(vault)).totalSupply();
        uint256 newTotalSupply = currentTotalSupply + sharesAmount;
        _setVaultTotalSupply(newTotalSupply);
    }

    function _reportDepositBatch(address container, uint256 nav0, uint256 nav1, uint256 notionRemainder) internal {
        notion.mint(container, notionRemainder);

        IVault.ContainerReport memory report;
        report.nav0 = nav0;
        report.nav1 = nav1;

        vm.prank(container);
        notion.approve(address(vault), notionRemainder);

        vm.prank(container);
        vault.reportDeposit(report, notionRemainder);
    }

    function _setVaultTotalSupply(uint256 totalSupply) internal {
        stdstore.target(address(vault)).sig(IERC20.totalSupply.selector).checked_write(totalSupply);
    }

    function _calculateExpectedSharesToWithdraw(
        uint256 sharesAmount,
        uint256 sharesPercent
    ) internal pure returns (uint256) {
        return (sharesAmount * sharesPercent) / MAX_BPS;
    }
}
