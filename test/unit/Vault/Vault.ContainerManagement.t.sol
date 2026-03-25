// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IVault} from "contracts/interfaces/IVault.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {L1Base} from "test/L1Base.t.sol";

contract VaultContainerManagementTest is L1Base {
    uint256 internal constant MAX_CONTAINERS = 255;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_AddContainer() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        (address[] memory containers, uint256[] memory weights) = vault.getContainers();
        assertEq(containers.length, 1, "test_AddContainer: containers length mismatch");
        assertEq(containers[0], address(container), "test_AddContainer: container mismatch");
        assertEq(weights[0], TOTAL_CONTAINER_WEIGHT, "test_AddContainer: weight mismatch");
        assertEq(vault.isContainer(address(container)), true, "test_AddContainer: isContainer mismatch");

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        (containers, weights) = vault.getContainers();
        assertEq(containers.length, 2, "test_AddContainer: containers length mismatch");
        assertEq(containers[0], address(container), "test_AddContainer: container mismatch");
        assertEq(containers[1], address(container2), "test_AddContainer: container2 mismatch");
        assertEq(weights[0], TOTAL_CONTAINER_WEIGHT, "test_AddContainer: weight mismatch");
        assertEq(weights[1], 0, "test_AddContainer: weight2 mismatch");
        assertEq(vault.isContainer(address(container2)), true, "test_AddContainer: isContainer2 mismatch");
    }

    function test_RevertIf_AddContainer_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        _addContainer(address(0), REMOTE_CHAIN_ID);
    }

    function test_RevertIf_AddContainer_ZeroChainId() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        vm.expectRevert(abi.encodeWithSelector(Errors.IncorrectChainId.selector, 0));
        _addContainer(address(container), 0);
    }

    function test_RevertIf_AddContainer_ContainerAlreadyExists() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        vm.expectRevert(IVault.ContainerAlreadyExists.selector);
        _addContainer(address(container), REMOTE_CHAIN_ID + 1);
    }

    function test_RevertIf_AddContainer_ContainerForChainIdAlreadyExists() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.ContainerForChainIdAlreadyExists.selector,
                REMOTE_CHAIN_ID,
                address(container1)
            )
        );
        _addContainer(address(container2), REMOTE_CHAIN_ID);
    }

    function test_RevertIf_AddContainer_LocalContainerWithRemoteChainId() public {
        IContainerLocal containerLocal = _deployContainerLocal();

        vm.expectRevert(IVault.IncorrectContainerType.selector);
        _addContainer(address(containerLocal), REMOTE_CHAIN_ID);
    }

    function test_RevertIf_AddContainer_IncorrectContainerType() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        vm.expectRevert(IVault.IncorrectContainerType.selector);
        _addContainer(address(container), block.chainid);

        IContainerLocal containerLocal = _deployContainerLocal();
        vm.expectRevert(IVault.IncorrectContainerType.selector);
        _addContainer(address(containerLocal), block.chainid + 1);
    }

    function test_RevertIf_AddContainer_MaxContainersReached() public {
        for (uint256 i = 0; i < MAX_CONTAINERS; ++i) {
            IContainerPrincipal container = _deployMockContainerPrincipal();
            _addContainer(address(container), REMOTE_CHAIN_ID + i);
        }

        IContainerPrincipal exceedingContainer = _deployMockContainerPrincipal();
        vm.expectRevert(IVault.MaxContainersReached.selector);
        _addContainer(address(exceedingContainer), REMOTE_CHAIN_ID + MAX_CONTAINERS);
    }

    function test_RevertIf_AddContainer_NotInIdleStatus() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();

        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.IncorrectVaultStatus.selector,
                IVault.VaultStatus.DepositBatchProcessingStarted
            )
        );
        _addContainer(address(container), REMOTE_CHAIN_ID);
    }

    function test_SetContainerWeights_RemoveContainer() public {
        uint256 containerNumber = 3;
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        IContainerLocal containerLocal = _deployContainerLocal();
        _addContainer(address(containerLocal), block.chainid);

        address[] memory containers = new address[](containerNumber);
        containers[0] = address(container1);
        containers[1] = address(container2);
        containers[2] = address(containerLocal);
        uint256[] memory weights = new uint256[](containerNumber);
        weights[0] = TOTAL_CONTAINER_WEIGHT;
        weights[1] = 0;
        weights[2] = 0;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();
        assertEq(containers.length, 1, "test_SetContainerWeights_RemoveContainer: containers length mismatch");
        assertEq(containers[0], address(container1), "test_SetContainerWeights_RemoveContainer: container1 mismatch");
        assertEq(weights[0], TOTAL_CONTAINER_WEIGHT, "test_SetContainerWeights_RemoveContainer: weight1 mismatch");
        assertEq(
            vault.isContainer(address(container2)),
            false,
            "test_SetContainerWeights_RemoveContainer: isContainer2 mismatch"
        );
        assertEq(
            vault.containerByChainId(REMOTE_CHAIN_ID),
            address(0),
            "test_SetContainerWeights_RemoveContainer: containerPrincipal1 for chain ID is not unset after removal"
        );
        assertEq(
            vault.containerByChainId(block.chainid),
            address(0),
            "test_SetContainerWeights_RemoveContainer: containerLocal for chain ID is not unset after removal"
        );
    }

    function test_SetContainerWeights_RemoveLastContainer() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 0;

        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();
        assertEq(
            containers.length,
            0,
            "test_SetContainerWeights_RemoveLastContainer: containers length should be zero"
        );
        assertEq(weights.length, 0, "test_SetContainerWeights_RemoveLastContainer: weights length should be zero");
    }

    function test_SetContainerWeights_RemoveMultipleContainers() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        IContainerPrincipal container3 = _deployMockContainerPrincipal();
        _addContainer(address(container3), REMOTE_CHAIN_ID + 2);

        IContainerPrincipal container4 = _deployMockContainerPrincipal();
        _addContainer(address(container4), REMOTE_CHAIN_ID + 3);

        address[] memory containers = new address[](4);
        containers[0] = address(container1);
        containers[1] = address(container2);
        containers[2] = address(container3);
        containers[3] = address(container4);
        uint256[] memory weights = new uint256[](4);
        weights[0] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[2] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[3] = TOTAL_CONTAINER_WEIGHT / containers.length;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        _sortContainersAndWeights(containers, weights);
        for (uint256 i = 0; i < containers.length; ++i) {
            weights[i] = containers[i] == address(container4) ? TOTAL_CONTAINER_WEIGHT : 0;
        }

        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();
        assertEq(containers.length, 1, "test_SetContainerWeights_RemoveMultipleContainers: containers length mismatch");
        assertEq(
            containers[0],
            address(container4),
            "test_SetContainerWeights_RemoveMultipleContainers: container4 mismatch"
        );
        assertEq(
            weights[0],
            TOTAL_CONTAINER_WEIGHT,
            "test_SetContainerWeights_RemoveMultipleContainers: weight4 mismatch"
        );
    }

    function test_SetContainerWeights_UpdateContainerWeights() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        address[] memory containers = new address[](2);
        containers[0] = address(container1);
        containers[1] = address(container2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT - weights[0];

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();

        assertEq(
            weights[0],
            TOTAL_CONTAINER_WEIGHT / containers.length,
            "test_SetContainerWeights_UpdateContainerWeights: weight1 mismatch"
        );
        assertEq(
            weights[1],
            TOTAL_CONTAINER_WEIGHT / containers.length,
            "test_SetContainerWeights_UpdateContainerWeights: weight2 mismatch"
        );

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < containers.length; ++i) {
            totalWeight += weights[i];
        }
        assertEq(
            totalWeight,
            TOTAL_CONTAINER_WEIGHT,
            "test_SetContainerWeights_UpdateContainerWeights: total weight mismatch"
        );
    }

    function test_SetContainerWeights_UpdateContainerWeights_DifferentWeights() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        IContainerPrincipal container3 = _deployMockContainerPrincipal();
        _addContainer(address(container3), REMOTE_CHAIN_ID + 2);

        IContainerPrincipal container4 = _deployMockContainerPrincipal();
        _addContainer(address(container4), REMOTE_CHAIN_ID + 3);

        address[] memory containers = new address[](4);
        containers[0] = address(container1);
        containers[1] = address(container2);
        containers[2] = address(container3);
        containers[3] = address(container4);
        uint256[] memory weights = new uint256[](4);
        uint256 evenWeight = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[0] = evenWeight;
        weights[1] = evenWeight;
        weights[2] = evenWeight;
        weights[3] = evenWeight;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();
        assertEq(
            containers.length,
            4,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: containers length mismatch"
        );
        assertEq(
            weights[0],
            evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: weight1 mismatch"
        );
        assertEq(
            weights[1],
            evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: weight2 mismatch"
        );
        assertEq(
            weights[2],
            evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: weight3 mismatch"
        );
        assertEq(
            weights[3],
            evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: weight4 mismatch"
        );

        weights[0] = evenWeight;
        weights[1] = 2 * evenWeight;
        weights[2] = evenWeight / 2;
        weights[3] = evenWeight / 2;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        (containers, weights) = vault.getContainers();
        assertEq(
            containers.length,
            4,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: containers length mismatch"
        );
        assertEq(
            weights[0],
            evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: updated weight1 mismatch"
        );
        assertEq(
            weights[1],
            2 * evenWeight,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: updated weight2 mismatch"
        );
        assertEq(
            weights[2],
            evenWeight / 2,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: updated weight3 mismatch"
        );
        assertEq(
            weights[3],
            evenWeight / 2,
            "test_SetContainerWeights_UpdateContainerWeights_DifferentWeights: updated weight4 mismatch"
        );
    }

    function test_RevertIf_SetContainerWeights_NotInIdleStatus() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](1);
        weights[0] = TOTAL_CONTAINER_WEIGHT;

        _setVaultStatus(IVault.VaultStatus.DepositBatchProcessingStarted);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.IncorrectVaultStatus.selector,
                IVault.VaultStatus.DepositBatchProcessingStarted
            )
        );
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_ArrayLengthMismatch() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / weights.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT / weights.length;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_DuplicateContainer() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        (address smaller, address larger) = address(container1) < address(container2)
            ? (address(container1), address(container2))
            : (address(container2), address(container1));
        address[] memory containers = new address[](3);
        containers[0] = smaller;
        containers[1] = larger;
        containers[2] = smaller; // duplicate breaks strict ascending order
        uint256[] memory weights = new uint256[](3);
        weights[0] = TOTAL_CONTAINER_WEIGHT / 3;
        weights[1] = TOTAL_CONTAINER_WEIGHT / 3;
        weights[2] = TOTAL_CONTAINER_WEIGHT - weights[0] - weights[1];

        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicatingContainer.selector, smaller));
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_WeightRoundsToZero() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        vm.prank(roles.configurator);
        vault.setMinDepositBatchSize(TOTAL_CONTAINER_WEIGHT - 1);

        (address smaller, address larger) = address(container1) < address(container2)
            ? (address(container1), address(container2))
            : (address(container2), address(container1));
        address[] memory containers = new address[](2);
        containers[0] = smaller;
        containers[1] = larger;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = TOTAL_CONTAINER_WEIGHT - 1;

        vm.expectRevert(abi.encodeWithSelector(IVault.WeightRoundsToZero.selector, smaller, 1));
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_ContainerNotFound() public {
        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();

        address[] memory containers = new address[](2);
        containers[0] = address(container);
        containers[1] = address(container2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / weights.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT / weights.length;

        _sortContainersAndWeights(containers, weights);
        vm.expectRevert(abi.encodeWithSelector(IVault.ContainerNotFound.selector, address(container2)));
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_WeightInvariantViolated() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        address[] memory containers = new address[](2);
        containers[0] = address(container1);
        containers[1] = address(container2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT / containers.length + 1;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vm.expectRevert(abi.encodeWithSelector(IVault.IncorrectWeights.selector, TOTAL_CONTAINER_WEIGHT + 1));
        vault.setContainerWeights(containers, weights);

        weights[0] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[1] = 1;
        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vm.expectRevert(
            abi.encodeWithSelector(IVault.IncorrectWeights.selector, TOTAL_CONTAINER_WEIGHT / containers.length + 1)
        );
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_ContainerRemovedWithoutWeightUpdate() public {
        IContainerPrincipal container1 = _deployMockContainerPrincipal();
        _addContainer(address(container1), REMOTE_CHAIN_ID);

        IContainerPrincipal container2 = _deployMockContainerPrincipal();
        _addContainer(address(container2), REMOTE_CHAIN_ID + 1);

        address[] memory containers = new address[](2);
        containers[0] = address(container1);
        containers[1] = address(container2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = TOTAL_CONTAINER_WEIGHT / containers.length;
        weights[1] = TOTAL_CONTAINER_WEIGHT - weights[0];

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);

        weights[1] = 0;

        _sortContainersAndWeights(containers, weights);
        vm.prank(roles.containerManager);
        vm.expectRevert(
            abi.encodeWithSelector(IVault.IncorrectWeights.selector, TOTAL_CONTAINER_WEIGHT / containers.length)
        );
        vault.setContainerWeights(containers, weights);
    }
}
