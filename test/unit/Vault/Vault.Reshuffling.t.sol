// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {L1Base} from "test/L1Base.t.sol";

contract VaultReshufflingTest is L1Base {
    using stdStorage for StdStorage;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_SetReshufflingGateway() public {
        address newGateway = makeAddr("NEW_RESHUFFLING_GATEWAY");

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(newGateway);

        assertEq(vault.reshufflingGateway(), newGateway, "test_SetReshufflingGateway: gateway mismatch");
    }

    function test_RevertIf_SetReshufflingGateway_InReshufflingMode() public {
        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(makeAddr("NEW_RESHUFFLING_GATEWAY"));
    }

    function test_RevertIf_SetReshufflingGateway_ZeroAddress() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(address(0));
    }

    function test_RevertIf_SetReshufflingGateway_SettingSameValue() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        address newGateway = makeAddr("NEW_RESHUFFLING_GATEWAY");
        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(newGateway);

        vm.expectRevert(Errors.SettingSameValue.selector);
        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(newGateway);
    }

    function test_EnableReshufflingMode() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        assertEq(vault.isReshuffling(), true, "test_EnableReshufflingMode: reshuffling mode mismatch");
    }

    function test_RevertIf_EnableReshufflingMode_AlreadyEnabled() public {
        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_RevertIf_EnableReshufflingMode_ReshufflingGatewayNotSet() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        stdstore.target(address(vault)).sig(vault.reshufflingGateway.selector).checked_write(address(0));

        vm.expectRevert(Errors.ReshufflingGatewayNotSet.selector);
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_RevertIf_EnableReshufflingMode_NotInIdleStatus() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.IncorrectVaultStatus.selector,
                IVault.VaultStatus.DepositBatchProcessingStarted
            )
        );
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_DisableReshufflingMode() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        address[] memory containers = new address[](2);
        containers[0] = address(container1);
        containers[1] = address(container2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / 2;
        weights[1] = TOTAL_CONTAINER_WEIGHT / 2;
        _sortContainersAndWeights(containers, weights);

        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        assertEq(vault.isReshuffling(), false, "test_DisableReshufflingMode: reshuffling mode mismatch");
    }

    function test_RevertIf_DisableReshufflingMode_AlreadyDisabled() public {
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.expectRevert(Errors.ReshufflingModeDisabled.selector);
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();
    }

    function test_RevertIf_DisableReshufflingMode_ZeroContainerWeight() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroContainerWeight.selector, address(container2)));
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();
    }
}
