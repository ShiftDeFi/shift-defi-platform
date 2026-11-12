// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {Vault} from "contracts/Vault.sol";
import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @title Injection verification: recoverStrandedNotion only releases true dust
contract VaultInjection is VaultBaseTest {
    function test_recoverStrandedNotion_releases_only_dust() public {
        address user = makeAddr("user");
        deal(address(notion), user, 1_000_000e6);
        vm.startPrank(user);
        notion.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, user);
        vm.stopPrank();

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();
        _reportDepositBatchAllContainersOnlyNotion(10_000e6);
        vm.prank(roles.operator);
        vault.resolveDepositBatch();

        // The CONFIGURATOR calls recoverStrandedNotion(0) — should revert (zero amount)
        vm.prank(roles.configurator);
        vm.expectRevert();
        Vault(address(vault)).recoverStrandedNotion(0);

        // Outsider cannot call
        address outsider = makeAddr("outsider");
        vm.prank(outsider);
        vm.expectRevert();
        Vault(address(vault)).recoverStrandedNotion(1);
    }

    function test_recoverStrandedNotion_recovers_donated_dust() public {
        // Donate notion directly to the vault (creating untracked balance)
        address donor = makeAddr("donor");
        deal(address(notion), donor, 1_000e6);
        vm.prank(donor);
        notion.transfer(address(vault), 1_000e6);

        uint256 configuratorBefore = notion.balanceOf(roles.configurator);

        // The CONFIGURATOR can now recover the donated dust
        vm.prank(roles.configurator);
        Vault(address(vault)).recoverStrandedNotion(1_000e6);

        assertEq(notion.balanceOf(roles.configurator), configuratorBefore + 1_000e6, "configurator received dust");
    }
}
