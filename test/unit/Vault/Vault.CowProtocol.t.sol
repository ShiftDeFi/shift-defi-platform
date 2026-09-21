// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {L1Base} from "test/L1Base.t.sol";

import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {MockContainerLocal} from "test/mocks/MockContainerLocal.sol";
import {MockContainerPrincipal} from "test/mocks/MockContainerPrincipal.sol";
import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";

/// @dev The Vault reads pendingCowOrderCount rather than calling requireNoPendingOrders.
contract VaultCowProtocolTest is L1Base {
    MockCowProtocolAdapter internal gatewayAdapter;

    uint256 internal constant PENDING_ORDERS = 2;

    function setUp() public override {
        super.setUp();

        gatewayAdapter = new MockCowProtocolAdapter(address(reshufflingGateway));

        vm.prank(roles.tokenManager);
        ICowProtocolModule(address(reshufflingGateway)).setCowAdapter(address(gatewayAdapter));
    }

    function _expectPendingCowOrders(address owner) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.PendingCowOrders.selector, owner, PENDING_ORDERS));
    }

    function test_RevertIf_EnableReshufflingMode_PendingCowOrdersOnGateway() public {
        gatewayAdapter.setPendingOrderCount(PENDING_ORDERS);

        _expectPendingCowOrders(address(reshufflingGateway));
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    /// @dev Registers this chain's container and gives it the whole weight. Requires the
    ///      reshuffling mode to be on.
    function _addWeightedLocalContainer() internal returns (IContainerLocal container) {
        container = _deployMockContainerLocal();
        _addContainer(address(container), block.chainid);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](1);
        weights[0] = TOTAL_CONTAINER_WEIGHT;

        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_EnableReshufflingMode_PendingCowOrdersOnLocalContainer() public {
        // addContainer is onlyInReshufflingMode.
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        IContainerLocal container = _addWeightedLocalContainer();

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        MockContainerLocal(address(container)).setPendingCowOrderCount(PENDING_ORDERS);

        _expectPendingCowOrders(address(container));
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function test_RevertIf_DisableReshufflingMode_PendingCowOrdersOnGateway() public {
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        gatewayAdapter.setPendingOrderCount(PENDING_ORDERS);

        _expectPendingCowOrders(address(reshufflingGateway));
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();
    }

    /// @dev The container branch of _requireNoPendingReshufflingCowOrders on the way out.
    function test_RevertIf_DisableReshufflingMode_PendingCowOrdersOnLocalContainer() public {
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        IContainerLocal container = _addWeightedLocalContainer();
        MockContainerLocal(address(container)).setPendingCowOrderCount(PENDING_ORDERS);

        _expectPendingCowOrders(address(container));
        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();
    }

    /// @dev Removal of a Local container, which also deletes containerByChainId[block.chainid].
    function test_RevertIf_SetContainerWeights_PendingCowOrdersOnLocalContainer() public {
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        IContainerLocal container = _deployMockContainerLocal();
        _addContainer(address(container), block.chainid);
        MockContainerLocal(address(container)).setPendingCowOrderCount(PENDING_ORDERS);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 0;

        _expectPendingCowOrders(address(container));
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetContainerWeights_PendingCowOrdersOnPrincipalContainer() public {
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        IContainerPrincipal container = _deployMockContainerPrincipal();
        _addContainer(address(container), REMOTE_CHAIN_ID);
        MockContainerPrincipal(address(container)).setPendingCowOrderCount(PENDING_ORDERS);

        address[] memory containers = new address[](1);
        containers[0] = address(container);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 0;

        _expectPendingCowOrders(address(container));
        vm.prank(roles.containerManager);
        vault.setContainerWeights(containers, weights);
    }

    function test_RevertIf_SetReshufflingGateway_PendingCowOrdersOnPreviousGateway() public {
        gatewayAdapter.setPendingOrderCount(PENDING_ORDERS);

        _expectPendingCowOrders(address(reshufflingGateway));
        vm.prank(roles.reshufflingManager);
        vault.setReshufflingGateway(makeAddr("NEW_RESHUFFLING_GATEWAY"));
    }
}
