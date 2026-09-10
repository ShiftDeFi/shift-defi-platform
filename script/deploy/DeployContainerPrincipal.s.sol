// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ContainerPrincipal} from "contracts/ContainerPrincipal.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployContainerPrincipal is RolesRegistry, DeploySaltedProxy {
    address public vaultAddress = vm.envAddress("VAULT_ADDRESS");
    address public notionAddress = vm.envAddress("NOTION_TOKEN_ADDRESS");
    address public swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

    address public messageRouterAddress = vm.envAddress("MESSAGE_ROUTER_ADDRESS");
    uint256 public remoteChainId = vm.envUint("REMOTE_CHAIN_ID");

    function run() public {
        _loadRoles();

        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams(
            vaultAddress,
            notionAddress,
            roles.defaultAdmin,
            roles.operator,
            roles.emergencyPauser,
            roles.tokenManager,
            swapRouterAddress
        );

        ICrossChainContainer.CrossChainContainerInitParams memory crossChainContainerInitParams = ICrossChainContainer
            .CrossChainContainerInitParams(
                messageRouterAddress,
                remoteChainId,
                roles.messengerManager,
                roles.bridgeAdapterManager
            );

        bytes memory data = abi.encodeWithSelector(
            ContainerPrincipal.initialize.selector,
            containerInitParams,
            crossChainContainerInitParams
        );

        vm.startBroadcast();
        address implementation = address(new ContainerPrincipal());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
