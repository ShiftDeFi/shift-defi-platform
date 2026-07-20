// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReshufflingGateway} from "contracts/ReshufflingGateway.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployReshufflingGateway is RolesRegistry, DeploySaltedProxy {
    address public vaultAddress = vm.envAddress("VAULT_ADDRESS");
    address public swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

    function run() public {
        _loadRoles();

        bytes memory data = abi.encodeWithSelector(
            ReshufflingGateway.initialize.selector,
            vaultAddress,
            swapRouterAddress,
            roles.defaultAdmin,
            roles.bridgeAdapterManager,
            roles.reshufflingExecutor,
            roles.tokenManager
        );

        vm.startBroadcast();
        address implementation = address(new ReshufflingGateway());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
