// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VaultBaseTest} from "test/unit/Vault/VaultBase.t.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultRepairingModeTest is VaultBaseTest {
    function test_ActivateRepairingMode() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));

        vm.prank(roles.emergencyManager);
        vault.activateRepairingMode();
        assertEq(vault.isRepairing(), true, "test_ActivateRepairingMode: vault should be in repairing mode");
    }

    function test_RevertIf_activateRepairingMode_NotInEmergencyManager() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                users.alice,
                EMERGENCY_MANAGER_ROLE
            )
        );
        vault.activateRepairingMode();
    }

    function test_RevertIf_activateRepairingMode_AlreadyInRepairingMode() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));
        vm.prank(roles.emergencyManager);
        vault.activateRepairingMode();
        vm.prank(roles.emergencyManager);
        vm.expectRevert(IVault.VaultIsInRepairingMode.selector);
        vault.activateRepairingMode();
    }

    function test_RevertIf_activateRepairingMode_ReshufflingGatewayNotSet() public {
        vm.prank(roles.emergencyManager);
        vm.expectRevert(IVault.ReshufflingGatewayNotSet.selector);
        vault.activateRepairingMode();
    }

    function test_ClaimReshufflingGateway() public {
        uint256 notionAmount = 1000 * 1e18;

        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistToken(address(notion));

        notion.mint(address(reshufflingGateway), notionAmount);
        _giveUserShares(users.alice, 1000 * 1e18);

        vm.prank(roles.emergencyManager);
        vault.activateRepairingMode();

        vm.prank(users.alice);
        vault.claimReshufflingGateway(users.alice);

        vm.assertEq(
            notion.balanceOf(users.alice),
            notionAmount,
            "test_ClaimReshufflingGateway: alice notion balance mismatch"
        );

        vm.prank(users.alice);
        vm.expectRevert(IVault.AlreadyClaimed.selector);
        vault.claimReshufflingGateway(users.alice);
    }

    function test_RevertIf_ClaimReshufflingGateway_VaultNotInRepairingMode() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));

        vm.prank(users.alice);
        vm.expectRevert(IVault.NotInRepairingMode.selector);
        vault.claimReshufflingGateway(users.alice);
    }
}
